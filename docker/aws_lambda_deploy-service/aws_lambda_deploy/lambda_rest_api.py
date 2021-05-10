import traceback

from flask import Flask, request, g
from flask_restplus import Api, Resource, fields, marshal_with
from kubernetes import client, config
import os, sys
import deploy_aws_lambda_api as lapi
import deploy_aws_lambda_ext as lapi_ext
import logging
import sqlite3
import socket
import subprocess
from subprocess import CompletedProcess
from subprocess import PIPE
import re
from flask_httpauth import HTTPBasicAuth
from werkzeug.security import generate_password_hash, check_password_hash


#Flask app config
flask_app = Flask(__name__)
api = Api(app = flask_app,
            version = "1.0",
            title = "LamdaDeploy",
            description = "Service used to deploy AWS Lambdas")

name_space_lambda = api.namespace('lambda', description='Lambda APIs')
name_space_kubernetes = api.namespace('kubernetes', description='Kubernetes APIs')
api.add_namespace(name_space_lambda)
api.add_namespace(name_space_kubernetes)

#Sqlite database
DATABASE_PATH = "lambdadeploy.db"

#Logging config
logging.basicConfig(stream=sys.stdout,
                    format='%(asctime)s %(levelname)s: %(message)s',
                    level=logging.WARN)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

#Auth config
auth = HTTPBasicAuth()

users = {
    "elisity-kubernetes": generate_password_hash("pMAlz9uVbI6ccvip0PNJ1UwwtLCgMowj")
}

@auth.verify_password
def verify_password(username, password):
    if username in users and \
            check_password_hash(users.get(username), password):
        return username


apigw_ip = ""

#Models
deploy_request = api.model('Deploy Lambda Request', \
          { \
            'regions' : fields.List(fields.String('List of aws-regions to deploy', required=True)), \
            'account_id' : fields.String(description='AWS Account ID', required=True), \
            'role_arn' : fields.String(description='AWS Role ARN', required=True), \
            'external_id' : fields.String(description='AWS externalId linked to Role ARN', required=True), \
            'gw_addr' : fields.String(description='Address of eSaaS ApiGw ip:port'), \
            's3_bucket' : fields.String(description='Name of S3 bucket for CloudWatch & Lambda'), \
            'zip_file_dir' : fields.String(description='Directory of zip files in local file system'), \
            'res_prefix' : fields.String(description='Prefix to be used for resource names'), \
            'token_refresh_rate' : fields.String(description='Rate (in minutes) at which auth token will be refreshed',default='25'), \
            'delete_res_only' : fields.String(description='Delete resource and exit. No resources will be created.'), \
            'overwrite' : fields.Boolean(description='Overwrite existing lambdas if they already exist.') \
          })

lambda_status_request = api.model('Deploy Job Status Request', \
          { \
            'region' : fields.String('List of aws-regions', required=True), \
            'account_id' : fields.String(description='AWS Account ID', required=True), \
          })
kubernetes_restart_deployment_request = api.model('Restart Kubernetes Service Request', \
          { \
            'deployments' : fields.List(fields.String('List of deployments to restart', required=True)), \
          })
kubernetes_restart_container_request = api.model('Restart Kubernetes Container Request', \
          { \
            'deployment_name' : fields.String('name of deployment where container is', required=True), \
            'container_name' : fields.String('name of container to restart', required=True), \
          })

def generate_job_key(region, account_id):
    bad_chars = [';', ':', '!', '*']
    key = f"{account_id}-{region}"
    for i in bad_chars :
        key = key.replace(i, '')
    return key

@name_space_lambda.route('/deploy')
class LambdaDeploy(Resource):

    @api.expect(deploy_request, validate=True)
    def post(self):
        req = get_content(deploy_request, api.payload)

        logger.info(f"Received request to deploy lambdas: {req}")
        try:
            process_deploy_request(req)

        except Exception as e:
            logger.error(f"error in deploying lambda: {e}")
            return {'message' : str(e)}, 500
        return {'result' : 'Deploy request submitted'}, 200

@name_space_kubernetes.route('/restart')
class RestartKubernetes(Resource):
    @api.expect(kubernetes_restart_deployment_request, validate=True)
    @auth.login_required
    def post(self):
        req = get_content(kubernetes_restart_deployment_request, api.payload)
        logger.info(f"Received request to restart deployments: {req}")
        try:
            result = []
            for deployment in req['deployments']:
                if restart_kubernetes_deployment(deployment):
                    result.append(deployment)

        except Exception as e:
            logger.error(f"error in restarting deployments: {e}")
            return {'message' : str(e)}, 500
        return {'success_list' : result}, 200


@name_space_kubernetes.route('/container/restart')
class RestartKubernetes(Resource):
    @api.expect(kubernetes_restart_container_request, validate=True)
    @auth.login_required
    def post(self):
        req = get_content(kubernetes_restart_container_request, api.payload)
        logger.info(f"Received request to restart container: {req}")
        try:
            success_list = []
            error_list = []

            if restart_container(req['deployment_name'], req['container_name']):
                success_list.append(req)
            else:
                error_list.append(req)

        except Exception as e:
            logger.error(f"error in restarting container: {e}")
            return {'message' : str(e)}, 500
        return {'success_list' : success_list, 'error_list' : error_list}, 200

def restart_kubernetes_deployment(deployment_name):
    logger.info(f"Restarting deployment: {deployment_name}")
    try:
        restart_cli = f"kubectl rollout restart deployment {deployment_name}"
        restart_cli = re.split(r'\s+', restart_cli)
        logger.info(" ".join(restart_cli))
        os_exec(restart_cli)
        return True
    except Exception as e:
        logger.error("error during restart of deployment")
    return False

def get_job_status(jobkey, retry):
    try:
        db = get_db()
        result = db.cursor().execute('select * from jobs where jobkey=?', (jobkey,)).fetchone()
        logger.info(f"Got result {result}")
    except Exception as e:
        logger.error(f"Error in db select {e}")
        if e.args[0].startswith('no such table') and retry:
            logger.info("Trying to re-init db...")
            init_db()
            return get_job_status(jobkey, False)

    return result



def process_deploy_request(req):
    if 'gw_addr' in req and req['gw_addr']:
        if ":" not in req['gw_addr']:
            req['gw_addr'] = req['gw_addr']+":443"
    else:
        req['gw_addr'] = get_apigw_ip()

    req['profile_id'] = "master"
    deploy_from_api(req)

def db_job_update(jobkey, **kwargs):
    if 'action' in kwargs:
        logger.info(f"updating db: job {jobkey}, action {kwargs['action']}")
        try:
            db = get_db()
            if(kwargs['action'] == "CREATE"):
                db.cursor().execute('insert or replace into jobs (jobkey, status) values (?, ?)', (jobkey, "CREATED"))

            elif(kwargs['action'] == "FAIL"):
                db.cursor().execute('update jobs set status=? where jobkey=?', ("FAILED",jobkey))
            elif(kwargs['action'] == "SKIP"):
                db.cursor().execute('update jobs set status=? where jobkey=?', ("SKIPPED",jobkey))
            elif(kwargs['action'] == "FINISH"):
                db.cursor().execute('update jobs set status=? where jobkey=?', ("FINISHED",jobkey))

            db.commit()
        except Exception as e:
            logger.error(f"Error in db update {e}")


        #logger.info(f"jobs: {query_db('select * from jobs')}")


def query_db(query, args=(), one=False):
    cur = get_db().execute(query, args)
    rv = cur.fetchall()
    cur.close()
    return (rv[0] if rv else None) if one else rv

def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE_PATH)
        def make_dicts(cursor, row):
            return dict((cursor.description[idx][0], value)
                for idx, value in enumerate(row))

        db.row_factory = make_dicts
    return db

@flask_app.teardown_appcontext
def close_db_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()

@flask_app.before_first_request
def init_db():
    with flask_app.app_context():
        logger.info("Start db setup")
        db = get_db()
        db.cursor().execute('''CREATE TABLE IF NOT EXISTS jobs
             (jobkey text, status text, PRIMARY KEY (jobkey))''')
        db.commit()
        logger.info("End db setup")


def deploy_from_api(options):
    try:
        logger.info(f"Deploying with options {options}")
        lapi.init(options)
        lapi_ext.init_ext(options)

        # Ensure lambda password is set in env variable
        # For a delete-only run, password is not required
        if not lapi.delete_res_only:
            lapi.lambda_pwd = os.environ.get('LAMBDA_PWD')
            lapi_ext.lambda_pwd = os.environ.get('LAMBDA_PWD')
            if lapi.lambda_pwd is None:
                raise Exception("Lambda password (LAMBDA_PWD) for API-GW is not available")

            lapi.get_lambda_function_code()
            lapi_ext.get_lambda_function_code_ext()

        if options['regions'] is not None:
            for region in options['regions']:
                jobkey = generate_job_key(region, options['account_id'])
                try:
                    curr_status = get_job_status(jobkey, True)
                    if curr_status and curr_status['status'] == "CREATED":
                        logger.info(f"Job for {jobkey} already in progress, skipping this deployment.")
                        db_job_update(jobkey, action="SKIP")
                        continue
                    db_job_update(jobkey, action="CREATE")
                    lapi.deploy_in_region(region)
                    lapi_ext.deploy_in_region_ext(region)
                except Exception as e:
                    logger.info(f"Job for {jobkey} failed, {e}")
                    traceback.print_exc()
                    db_job_update(jobkey, action="FAIL", reason=e)
                    continue
                db_job_update(jobkey, action="FINISH")
    except Exception as e:
        raise Exception(e)
    finally:
        lapi.remove_cred_file_from_local_dir()


def get_content(api_model, json):
   @marshal_with(api_model)
   def get_request(json):
      return json
   return get_request(json)


def restart_container(deployment_name, container_name):
    try:
        config.load_kube_config()
        v1=client.CoreV1Api()
        ret = v1.list_pod_for_all_namespaces(watch=False)
        for i in ret.items:
            if deployment_name in i.metadata.name:
                restart_cli = f"kubectl exec {i.metadata.name} -c {container_name} -- /bin/sh -c \"kill 1\""
                logger.info(restart_cli)
                os_exec_shell(restart_cli)
        return True
    except Exception as e:
        logger.error(f"Could not restart container: {e}")
        return False

def get_apigw_ip():
    global apigw_ip
    if apigw_ip: return apigw_ip
    gw_ip = os.environ.get('API_GW')
    if gw_ip is not None:
        apigw_ip = f"{gw_ip}:443"
        return apigw_ip
    try:
        config.load_kube_config()
        v1=client.CoreV1Api()
        ret = v1.list_service_for_all_namespaces()
        for i in ret.items:
            if(i.spec.type == 'LoadBalancer'):
                gw_hostname = i.status.load_balancer.ingress[0].hostname
                gw_ip = socket.gethostbyname(gw_hostname) #currently will give any 1 of the ips at random, if there are multiple
                apigw_ip = f"{gw_ip}:443"
                return apigw_ip

    except Exception as e:
        logger.error(f"Could not get apigw ip: {e}")
        raise Exception(e)
def os_exec(args):
    # utility to execute os-commands/programs
    # e.g.  os_exec(['ls', '-l'])
    proc: CompletedProcess = subprocess.run(args, stdout=PIPE, stderr=PIPE)
    logger.debug(proc.stdout.decode("utf-8"))
    e_stderr = proc.stderr.decode("utf-8")
    if e_stderr:
        logger.error(e_stderr)
    logger.info(f"Return code for os-cmd: {proc.returncode}")
    return proc

def os_exec_shell(cmd):
    p = subprocess.Popen(cmd, universal_newlines=True, shell=True,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = p.stdout.read()
    retcode = p.wait()
    logger.info(f"Return code for os-cmd: {retcode} {text}")

if __name__ == '__main__':
    flask_app.run(host='0.0.0.0',debug=True)
