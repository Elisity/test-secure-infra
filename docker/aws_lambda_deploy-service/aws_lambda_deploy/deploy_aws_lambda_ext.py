#!/usr/bin/python3
#
# Automation script for deploying elisity lambda functions
# Based on deploy_aws_lambda.py
# Josh Tai
# October 2020
# ------------------------------------------------------

"""
    Note: Gatwway port is defaulted to 443 if not provided as part of gw_addr option
"""

import argparse
import logging
import os
import re
import subprocess
import sys
import time
import uuid
import zipfile
from subprocess import CompletedProcess
from subprocess import PIPE
from typing import Dict
import shutil

import boto3
from botocore.exceptions import ClientError

logging.basicConfig(stream=sys.stdout,
                    format='%(asctime)s %(levelname)s: %(message)s',
                    level=logging.WARN)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

role_arn = ""
external_id = ""

account_id = ""
profile_id = ""
aws_region = ""
gw_addr = ""
api_gw_host = ""
api_gw_port = ""
zip_file_dir = ""
retryCountRefresh = "20"  # has to be string
retryWaitMillisRefresh = "3000"  # has to string
retryCount = "10"  # has to be string
retryWaitMillis = "5000"  # has to be string
tokenRefreshRateMinutes = ""
delete_res_only = False
overwrite = False

aws_profile = ""
user_home = os.environ['HOME'] if 'HOME' in os.environ else "."
client_token = str(uuid.uuid4())
script_path = os.path.dirname(os.path.realpath(__file__))
build_dir = f'{script_path}/build_ext'

# cl_tr_client = boto3.client('cloudtrail')
# cw_logs_client = boto3.client('logs')

resource_prefix = ""
esaas_appsvc_path = "/api/v1/devsvc/external/aws/ec2/event"  # "/api/v1/appsvc/external"
esaas_login_path = "/api/v1/iam/internalaccounts/login"
esaas_auth_refresh_path = "/api/v1/iam/internalaccounts/refreshtoken"
esaas_config_update_path = "/api/v1/cloudconfig/external/aws/config/event"
elisity_s3_bucket_name = ''
elisity_cred_s3_object_key = '/elisity/cred/lambda-apigw'
elisity_lambda_exec_role_name = ''
elisity_lambda_exec_policy_name = ''

elisity_config_update_lf_name = ''
elisity_config_update_rule_name = ''


def get_assumed_role_client_ext(aws_service, **kwargs):
    global role_arn, external_id

    session = boto3.Session(profile_name=profile_id)
    sts_client = session.client('sts')
    assumed_role_object = sts_client.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"ElisityAssumedRoleSession-{session.profile_name}",
        ExternalId=external_id)
    credentials = assumed_role_object['Credentials']
    try:
        client = boto3.client(aws_service,
                              region_name=aws_region,
                              aws_access_key_id=credentials['AccessKeyId'],
                              aws_secret_access_key=credentials['SecretAccessKey'],
                              aws_session_token=credentials['SessionToken'],
                              **kwargs)
    except Exception as e:
        logger.error(f"Exception in getting assumed role: {e}")
        raise Exception(e)
    logger.info(f"Got {aws_service} client for region {client.meta.region_name}")
    return client


def get_assumed_role_session_ext(**kwargs):
    global role_arn, external_id

    session = boto3.Session(profile_name=profile_id)
    sts_client = session.client('sts')
    assumed_role_object = sts_client.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"ElisityAssumedRoleSession-{session.profile_name}",
        ExternalId=external_id)
    credentials = assumed_role_object['Credentials']
    try:
        session = boto3.Session(region_name=aws_region,
                                aws_access_key_id=credentials['AccessKeyId'],
                                aws_secret_access_key=credentials['SecretAccessKey'],
                                aws_session_token=credentials['SessionToken'],
                                **kwargs)
    except Exception as e:
        logger.error(f"Exception in getting assumed role for session: {e}")
        raise Exception(e)
    logger.info(f"Got session: {session}")
    return session


def get_lambda_function_code_ext():
    # Lambda JS function source files should be in child dir of Lambda-Deploy code
    src_dir = f'{script_path}/..'
    if not os.path.exists(build_dir):
        os.mkdir(build_dir)
    else:
        for bf in [f for f in os.listdir(build_dir) if os.path.isfile(os.path.join(build_dir, f))]:
            os.remove(os.path.join(build_dir, bf))

    this_file = "elisityConfigChgLF.js"
    fm = f"{src_dir}/aws_lambda_function/{this_file}"
    if not (os.path.exists(fm)):
        raise Exception(f'Unable to copy file {fm}. File not found.')
    logger.info(f"copying {fm}")
    shutil.copy(fm, build_dir)


def create_lambda_upload_zip_file_ext(upload_file_name):
    if not upload_file_name:
        raise Exception("Upload file name is empty")

    os.chdir(build_dir)

    if not os.path.exists(upload_file_name):
        raise Exception(f"Upload file does not exist {upload_file_name}")

    if re.match(r'\.zip$', upload_file_name):
        # The upload_file is alrady a .zip file. (unlike *.js or *.py)
        logger.info("Upload file is already zipped. No need to create zip.")
        return upload_file_name

    if not re.match(r'^.*\.(js|py)$', upload_file_name):
        raise Exception("Only Javascript/Python source is supported by this installer.")

    zip_file = re.sub(r'\.(js|py)$', '', upload_file_name) + ".zip"
    if os.path.exists(zip_file):
        logger.info(f"No need to create file {upload_file_name}, it already exists.")
        return zip_file

    with zipfile.ZipFile(zip_file, 'w') as myzip:
        myzip.write(upload_file_name)

    time.sleep(2)

    if not os.path.exists(f'{build_dir}/{zip_file}'):
        raise Exception(f"Unable to create zip file {build_dir}/{zip_file} for uploading to lambda")
    return zip_file


def create_lf_util_ext(lf_name, lf_handler, lf_upload_fname, lf_run_time="nodejs10.x"):
    logger.info(f"Going to create lambda function {lf_name}")
    lf_zip_fname = create_lambda_upload_zip_file_ext(lf_upload_fname)

    lambda_client = get_assumed_role_client_ext('lambda')

    with open(f"{build_dir}/{lf_zip_fname}", 'rb') as file_data:
        bytes_content = file_data.read()

        try:
            lambda_client.create_function(
                FunctionName=lf_name,
                Runtime=lf_run_time,
                Role=f"arn:aws:iam::{account_id}:role/{elisity_lambda_exec_role_name}",
                Handler=lf_handler,
                Code={'ZipFile': bytes_content},
                Timeout=180,
                MemorySize=256,
                Publish=True
            )
        except ClientError as e:
            ecode = e.response['Error']['Code']
            logger.error(f"Exception {ecode} while creationg lambda "
                         f"for Lambda Func {lf_name}")
            raise Exception(e)


def update_env_vars_for_lambda_func_ext(lf_name, env_vars):
    logger.info(f"Going to update env-vars for lam-func {lf_name}")
    lambda_client = get_assumed_role_client_ext('lambda')

    try:
        lambda_client.update_function_configuration(
            FunctionName=lf_name,
            Environment=env_vars
        )
        logger.info(f"SUCCESS - Updated env-vars for lam-func {lf_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"Exception {ecode} while updating env-vars "
                     f"for Lambda Func {lf_name}")
        raise Exception(e)


def create_lf_for_config_change():
    evars = {
        "Variables":
            {
                "retryCount": retryCountRefresh,
                "retryWaitMillis": retryWaitMillisRefresh,
                "s3Bucket": elisity_s3_bucket_name,
                "apiGwHost": api_gw_host,
                "apiGwPort": api_gw_port,
                "apiGwPath": esaas_login_path,
                "apiGwAuthRefreshPath": esaas_auth_refresh_path,
                "cloudConfigSvcPath": esaas_config_update_path
            }
    }
    create_lf_util_ext(
        lf_name=elisity_config_update_lf_name,
        lf_handler="elisityConfigChgLF.handler",
        lf_upload_fname="elisityConfigChgLF.js")

    wait_sec_for_func_creation = 8
    logger.info(f"Wait {wait_sec_for_func_creation} seconds for lambda "
                f"function {elisity_config_update_lf_name} to be deployed..")
    time.sleep(wait_sec_for_func_creation)
    update_env_vars_for_lambda_func_ext(elisity_config_update_lf_name, evars)


def configure_and_create_all_lambda_functions_ext():
    # get_lambda_function_code()   # Moved to the  start of script to ensure pre-requisites
    # create_lambda_execution_role()
    create_lf_for_config_change()


def create_event_source_mapping_ext(event_source_arn, func_name):
    # Needed when cloud-trail events are used
    lambda_client = get_assumed_role_client_ext('lambda')

    lambda_client.create_event_source_mapping(
        EventSourceArn=event_source_arn,
        FunctionName=func_name,
        Enabled=True)

    logger.info(f"Event-Source-Mapping SUCCESS {event_source_arn} <=> {func_name}")


def add_trigger_to_lambda_func_ext(func_name, rule_arn, rule_name):
    logger.info(f"Going to add trigger to Func {func_name} <- {rule_name}")
    lambda_client = get_assumed_role_client_ext('lambda')
    try:
        lambda_client.add_permission(
            FunctionName=func_name,
            StatementId=f"{rule_name}-Event",
            Action='lambda:InvokeFunction',
            Principal='events.amazonaws.com',
            SourceArn=rule_arn
        )
        logger.info(f"Add trigger to Func SUCCESS {func_name} <- {rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"Add trigger to Func {func_name} <- {rule_name} - Exception {ecode}")
        raise Exception(e)


def put_target_ext(ev_client, rule_name, lambda_fn_arn, lambda_fn_name, target_id="1"):
    logger.info(f"Going to put targets for Rule {rule_name} <- {lambda_fn_name}")
    try:
        ev_client.put_targets(
            Rule=rule_name,
            Targets=[
                {
                    'Arn': lambda_fn_arn,
                    'Id': target_id,
                }
            ]
        )
        logger.info(f"put_target: SUCCESS {rule_name} <- {lambda_fn_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"put_target: {ecode} Exception {rule_name} <- {lambda_fn_name}")
        raise Exception(e)


def create_rule_ext(ev_client, rule_name, events, role_arn, lambda_fn_arn, lambda_fn_name):
    logger.info(f"Going to create RULE {rule_name}")
    try:
        response = ev_client.put_rule(
            Name=rule_name,
            EventPattern=events,
            State='ENABLED',
            RoleArn=role_arn
        )
        logger.info(f"Create Rule SUCCESS - {rule_name}")
        rule_arn = response['RuleArn']
    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"create rule: {ecode} Exception {rule_name}")
        raise Exception(e)

    add_trigger_to_lambda_func_ext(lambda_fn_name, rule_arn, rule_name)
    put_target_ext(ev_client, rule_name, lambda_fn_arn, lambda_fn_name)
    return rule_arn


def create_cloudwatch_rules_for_lambda_ext():
    logger.info("Going to create ALL Cloud Watch Rules for Lambda")
    events_client = get_assumed_role_client_ext('events')

    # Config Changes Rule
    rule_arn_for_config_chg_rule = create_rule_ext(
        ev_client=events_client,
        rule_name=elisity_config_update_rule_name,
        role_arn=f"arn:aws:iam::{account_id}:role/{elisity_lambda_exec_role_name}",
        lambda_fn_arn=f"arn:aws:lambda:{aws_region}:{account_id}:function:{elisity_config_update_lf_name}",
        lambda_fn_name=elisity_config_update_lf_name,
        events="""
                {
                  "detail-type": [
                    "Config Configuration Item Change"
                  ],
                  "source": [
                    "aws.config"
                  ],
                  "detail": {
                    "configurationItem": {
                      "resourceType": [
                        "AWS::EC2::Subnet",
                        "AWS::EC2::VPC"
                      ],
                      "configurationItemStatus": [
                        "ResourceDiscovered",
                        "ResourceDeleted",
                        "OK"
                      ]
                    }
                  }
                }
                     """.strip()
    )


# noinspection DuplicatedCode
def clear_existing_setup_ext():
    logger.info("Going to clean-up existing rules, policies, roles, lambda-functions, etc.")

    session = get_assumed_role_session_ext()
    lambda_client = session.client('lambda', region_name=aws_region)

    logger.info(f"Going to remove trigger {elisity_config_update_rule_name} "
                f"from lambda function {elisity_config_update_lf_name}")
    try:
        lambda_client.remove_permission(
            FunctionName=elisity_config_update_lf_name,
            StatementId=f"{elisity_config_update_rule_name}-Event"
        )
        logger.info(f"REMOVE trigger SUCCESS {elisity_config_update_rule_name} "
                    f"from lambda function {elisity_config_update_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(f"No need to REMOVE trigger - {elisity_config_update_rule_name} "
                        f"from lambda function {elisity_config_update_lf_name}")
        else:
            logger.error(f"REMOVE trigger EXCEPTION {ecode} - {elisity_config_update_rule_name} "
                         f"from lambda function {elisity_config_update_lf_name}")
            raise Exception(e)

    # --------------------------------------------------------------------------

    # --- Remove targets from Rule (lambda-funcitons associated with Rule)
    logger.info(f"Going to REMOVE targets from RULE {elisity_config_update_rule_name}")
    events_client = session.client('events', region_name=aws_region)
    try:
        events_client.remove_targets(
            Rule=elisity_config_update_rule_name, Ids=["1"], Force=True)
        logger.info(f"Remove Target SUCCESS {elisity_config_update_rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to remove target for {elisity_config_update_rule_name}")
        else:
            logger.error(f"Error {ecode} while Removing Target {elisity_config_update_rule_name}")
            raise Exception(e)

    # --------------------------------------------------------------------------
    logger.info(f"Going to DELETE lambda function {elisity_config_update_lf_name}")
    try:
        lambda_client.delete_function(FunctionName=elisity_config_update_lf_name)
        logger.info(f"Delete lam-func SUCCESS {elisity_config_update_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete lam-func {elisity_config_update_lf_name}")
        else:
            logger.error(f"Error {ecode} deleting lam-func {elisity_config_update_lf_name}")
            raise Exception(e)
    # ----------------------------------------------------------------------------

    logger.info(f"Going to DELETE RULE {elisity_config_update_rule_name}")
    events_client = session.client('events', region_name=aws_region)
    try:
        events_client.delete_rule(Name=elisity_config_update_rule_name, Force=True)
        logger.info(f"Delete Rule SUCCESS {elisity_config_update_rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete rule {elisity_config_update_rule_name}")
        else:
            logger.error(f"Error {ecode} while Deleting rule {elisity_config_update_rule_name}")
            raise Exception(e)


def get_options() -> Dict[str, str]:
    parser = argparse.ArgumentParser(description='Deploy Elisity AWS Lambda Functions.', )
    parser.add_argument('-r', '--regions', type=str, nargs='+', required=True,
                        help='List of aws-regions to deploy')
    parser.add_argument('-a', '--account_id', type=str, required=True,
                        help='AWS Account ID')
    parser.add_argument('-p', '--profile_id', type=str, nargs='?',
                        help='AWS-CLI Profile ID')
    parser.add_argument('-g', '--gw_addr', type=str, required=True,
                        help='Address of eSaaS ApiGw ip:port')
    parser.add_argument('-s', '--s3_bucket', type=str, required=False,
                        help='Name of S3 bucket for CloudWatch & Lambda')
    parser.add_argument('-z', '--zip_file_dir', type=str, required=False,
                        help='Directory of zip files in local file system')
    parser.add_argument('-n', '--res_prefix', type=str, required=False,
                        help='Prefix to be used for resource names - default "elisity"')
    parser.add_argument('-T', '--token_refresh_rate', type=str, required=False, default='25',
                        help='Rate (in minutes) at which auth token will be refreshed')

    parser.add_argument('-d', '--delete_res_only', action='store_true', required=False,
                        help='Delete resource and exit. No resources will be crated.')

    args = parser.parse_args()
    options = vars(args)
    return options


def deploy_in_region_ext(region):
    global aws_region, elisity_s3_bucket_name, \
        elisity_lambda_exec_role_name, \
        elisity_lambda_exec_policy_name, \
        overwrite

    aws_region = region
    elisity_s3_bucket_name = f"{resource_prefix}-elisity-{account_id}-{region}"
    elisity_lambda_exec_role_name = f"{resource_prefix}elisityLambdaExecRole-{region}"
    elisity_lambda_exec_policy_name = f"{resource_prefix}elisityLambdaExecPolicy-{region}"
    logger.info(f"roles name: {elisity_lambda_exec_role_name}")
    logger.info(f"policy name: {elisity_lambda_exec_policy_name}")

    if not overwrite and check_lambda_exists_ext():
        logger.info(f"Lambda function already exists in {aws_region} and overwrite is disabled, skipping deployment.")
        return

    clear_existing_setup_ext()
    logger.info(f"25 delete_res_only {delete_res_only}")
    if delete_res_only:
        return
    configure_and_create_all_lambda_functions_ext()
    create_cloudwatch_rules_for_lambda_ext()


def check_lambda_exists_ext():
    logger.info(f"Checking if lambda function already exists: {elisity_config_update_lf_name}")

    session = get_assumed_role_session_ext()
    lambda_client = session.client('lambda', region_name=aws_region)
    try:
        response = lambda_client.get_function(FunctionName=elisity_config_update_lf_name)
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(
                f"Lambda fn not found: {elisity_config_update_lf_name}.")
            return False
    return True


def init_ext(options):
    global aws_profile, account_id, profile_id, api_gw_host, api_gw_port, gw_addr, role_arn, external_id, \
        resource_prefix, zip_file_dir, \
        elisity_s3_bucket_name, \
        elisity_lambda_exec_role_name, \
        elisity_lambda_exec_policy_name, \
        tokenRefreshRateMinutes, \
        delete_res_only, \
        elisity_config_update_rule_name, \
        elisity_config_update_lf_name, \
        overwrite

    if options['overwrite'] is not None and options['overwrite'] is True:
        overwrite = True

    if options['delete_res_only'] is not None and options['delete_res_only'] == "true":
        delete_res_only = True
    else:
        delete_res_only = False

    if options['profile_id'] is not None:
        aws_profile = " --profile " + options['profile_id'] + " "
        profile_id = options['profile_id']

    account_id = options['account_id'] if options['account_id'] is not None else ''

    if options['s3_bucket'] is not None:
        elisity_s3_bucket_name = options['s3_bucket']

    if options['zip_file_dir'] is not None:
        zip_file_dir = options['zip_file_dir'] + "/"

    if options['token_refresh_rate'] is not None:
        tokenRefreshRateMinutes = options['token_refresh_rate']
    else:
        tokenRefreshRateMinutes = 2  # 25 earlier

    gw_addr = options['gw_addr']
    api_gw_host, api_gw_port = gw_addr.split(':')
    if not api_gw_host:
        raise Exception(f"Invalid value for gateway address {gw_addr}")

    if not api_gw_port:
        logger.info("gw_addr has no port info. Port is defaulted to 443")
        api_gw_port = "443"

    resource_prefix = options['res_prefix'] if options['res_prefix'] is not None else 's1'

    if len(resource_prefix) > 10:
        raise Exception(f"Invalid value for resource prefix {resource_prefix}. "
                        "Length should be <= 10 chars")
    if re.search(r'[^a-z0-9-]', resource_prefix):
        raise Exception(f"Invalid value for resource prefix {resource_prefix}."
                        " Can contain only lowercase chars, number and hyphen.")

    elisity_config_update_rule_name = f"{resource_prefix}elisityConfigChgRule"
    elisity_config_update_lf_name = f"{resource_prefix}elisityConfigChgLF"

    if options['role_arn'] is not None:
        role_arn = options['role_arn']
    else:
        raise Exception("Role ARN is required.")

    if options['external_id'] is not None:
        external_id = options['external_id']
    else:
        raise Exception("ExternalId is required.")

    return options



def deploy_ext():
    options = get_options()
    init_ext(options)

    # Ensure lambda password is set in env variable
    # For a delete-only run, password is not required
    if not delete_res_only:
        lambda_pwd = os.environ.get('LAMBDA_PWD')
        if lambda_pwd is None:
            raise Exception("Lambda password (LAMBDA_PWD) for API-GW is not available")

        get_lambda_function_code_ext()

    if options['regions'] is not None:
        for region in options['regions']:
            deploy_in_region_ext(region)


def main():
    try:
        deploy_ext()
    except Exception as e:
        raise Exception(e)


if __name__ == '__main__':
    main()
