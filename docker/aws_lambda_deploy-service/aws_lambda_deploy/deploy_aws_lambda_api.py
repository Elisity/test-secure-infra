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
from pathlib import Path
import shutil

import boto3
from botocore.exceptions import ClientError

logging.basicConfig(stream=sys.stdout,
                    format='%(asctime)s %(levelname)s: %(message)s',
                    level=logging.WARN)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


role_arn=""
external_id=""

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
build_dir = f'{script_path}/build'

# cl_tr_client = boto3.client('cloudtrail')
# cw_logs_client = boto3.client('logs')

resource_prefix = ""
esaas_appsvc_path = "/api/v1/devsvc/external/aws/ec2/event"   # "/api/v1/appsvc/external"
esaas_login_path = "/api/v1/iam/internalaccounts/login"
esaas_auth_refresh_path = "/api/v1/iam/internalaccounts/refreshtoken"
elisity_s3_bucket_name = ''
elisity_cred_s3_object_key = '/elisity/cred/lambda-apigw'
elisity_lambda_exec_role_name = ''
elisity_lambda_exec_policy_name = ''
elisity_tag_chg_rule_name = ''
elisity_state_chg_rule_name = ''
elisity_tag_and_state_chg_lf_name = ''
elisity_auth_refresh_lf_name = ''
elisity_auth_refresh_rule_name = ''
elisity_eni_tag_create_lf_name = ''


def get_assumed_role_client(aws_service, **kwargs):
    global role_arn, external_id

    session = boto3.Session(profile_name=profile_id)
    sts_client = session.client('sts')
    assumed_role_object=sts_client.assume_role( \
        RoleArn=role_arn,\
        RoleSessionName=f"ElisityAssumedRoleSession-{session.profile_name}", \
        ExternalId=external_id)
    credentials=assumed_role_object['Credentials']
    try:
        client = boto3.client(aws_service,\
        region_name=aws_region,\
        aws_access_key_id=credentials['AccessKeyId'],\
        aws_secret_access_key=credentials['SecretAccessKey'],\
        aws_session_token=credentials['SessionToken'],\
        **kwargs)
    except Exception as e:
        logger.error(f"Exception in getting assumed role: {e}")
        raise Exception(e)
    logger.info(f"Got {aws_service} client for region {client.meta.region_name}")
    return client

def get_assumed_role_session(**kwargs):
    global role_arn, external_id

    session = boto3.Session(profile_name=profile_id)
    sts_client = session.client('sts')
    assumed_role_object=sts_client.assume_role( \
        RoleArn=role_arn,\
        RoleSessionName=f"ElisityAssumedRoleSession-{session.profile_name}", \
        ExternalId=external_id)
    credentials=assumed_role_object['Credentials']
    try:
        session = boto3.Session(region_name=aws_region,\
        aws_access_key_id=credentials['AccessKeyId'],\
        aws_secret_access_key=credentials['SecretAccessKey'],\
        aws_session_token=credentials['SessionToken'],\
        **kwargs)
    except Exception as e:
        logger.error(f"Exception in getting assumed role for session: {e}")
        raise Exception(e)
    logger.info(f"Got session: {session}")
    return session


def get_lambda_function_code():
    # Lambda JS function source files should be in child dir of Lambda-Deploy code
    src_dir = f'{script_path}/..'
    if not os.path.exists(build_dir):
        os.mkdir(build_dir)
    else:
        for bf in [f for f in os.listdir(build_dir) if os.path.isfile(os.path.join(build_dir, f))]:
            os.remove(os.path.join(build_dir, bf))

    this_file = 'tagEniESaaS.py'
    fm = f"{src_dir}/{this_file}"
    if not (os.path.exists(fm)):
        raise Exception(f'Unable to copy file {fm}. File not found.')
    logger.info(f"copying {fm}")
    shutil.copy(fm, build_dir)

    for this_file in "elisityTagAndStateChgLF.js elisityTokenRefreshLF.js".split(' '):
        fm = f"{src_dir}/aws_lambda_function/{this_file}"
        if not (os.path.exists(fm)):
            raise Exception(f'Unable to copy file {fm}. File not found.')
        logger.info(f"copying {fm}")
        shutil.copy(fm, build_dir)


def create_lambda_upload_zip_file(upload_file_name):
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


def create_lf_util(lf_name, lf_handler, lf_upload_fname, lf_run_time="nodejs10.x"):
    logger.info(f"Going to creare lambda function {lf_name}")
    lf_zip_fname = create_lambda_upload_zip_file(lf_upload_fname)


    lambda_client = get_assumed_role_client('lambda')

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


def create_lambda_execution_role():
    logger.info(f"Going to create lambda execution ROLE {elisity_lambda_exec_role_name}")
    iam_client = get_assumed_role_client('iam')

    role_resp = iam_client.create_role(
        RoleName=elisity_lambda_exec_role_name,
        AssumeRolePolicyDocument="""
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Principal": {
                    "Service": [ "lambda.amazonaws.com", "events.amazonaws.com" ]
                  },
                  "Action": "sts:AssumeRole"
                }
              ]
            }
            """.lstrip())

    logger.info(f"Create Role SUCCESS {elisity_lambda_exec_role_name}")

    logger.info(f"Going to create lambda exec POLICY {elisity_lambda_exec_policy_name}")
    policy_doc = """
        {
           "Version": "2012-10-17",
           "Statement": [
              {
                 "Sid": "CloudWatchEventsFullAccess",
                 "Effect": "Allow",
                 "Action": "events:*",
                 "Resource": "*"
              },
              {
                 "Sid": "IAMPassRoleForCloudWatchEvents",
                 "Effect": "Allow",
                 "Action": "iam:PassRole",
                 "Resource": "arn:aws:iam::*:role/AWS_Events_Invoke_Targets"
              },
              {
                 "Sid": "awslambda1",
                 "Effect": "Allow",
                 "Action": [
                    "lambda:*",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "ec2:Describe*",
                    "ec2:CreateTags",
                    "logs:DescribeLogStreams"
                 ],
                 "Resource": "*"
              },
              {
                  "Sid": "ListObjectsInBucket",
                  "Effect": "Allow",
                  "Action": [

                      "s3:ListBucket",
                      "s3:GetBucketLocation"
                  ],
                  "Resource": [
                      "arn:aws:s3:::<BUCKET_NAME>"
                  ]
              },
              {
                  "Sid": "ReadWriteS3",
                  "Effect": "Allow",
                  "Action": [
                      "s3:ListBucket",
                      "s3:PutObject",
                      "s3:GetObject"],
                  "Resource":  "*"
              }
           ]
        }""".strip()
    policy_doc = policy_doc.replace('<BUCKET_NAME>', elisity_s3_bucket_name)

    iam_client.create_policy(
        PolicyDocument=policy_doc,
        PolicyName=elisity_lambda_exec_policy_name
    )
    logger.info(f"Create lambda exec Policy SUCCESS {elisity_lambda_exec_policy_name}")

    logger.info(f"Going to Attach exec POLICY to ROLE {elisity_lambda_exec_role_name}")
    iam_client.attach_role_policy(
        PolicyArn=f"arn:aws:iam::{account_id}:policy/{elisity_lambda_exec_policy_name}",
        RoleName=elisity_lambda_exec_role_name)
    logger.info(f"Attach Policy to Role: SUCCESS {elisity_lambda_exec_role_name}")
    logger.info("Wait for few seconds for Lambda Exec Role creation\n")
    time.sleep(10)
    return role_resp


def update_env_vars_for_lambda_func(lf_name, env_vars):
    logger.info(f"Going to update env-vars for lam-func {lf_name}")
    lambda_client = get_assumed_role_client('lambda')

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


def create_lf_for_appsvc():
    evars = {
        "Variables":
            {
                "eKafkaBroker": "NOT-USED",
                "retryCount": retryCount,
                "retryWaitMillis": retryWaitMillis,
                "s3Bucket": elisity_s3_bucket_name,
                "apiGwHost": api_gw_host,
                "apiGwPort": api_gw_port,
                "appsvcPath": esaas_appsvc_path
            }
    }
    create_lf_util(
        lf_name=elisity_tag_and_state_chg_lf_name,
        lf_handler="elisityTagAndStateChgLF.handler",
        lf_upload_fname="elisityTagAndStateChgLF.js")

    wait_sec_for_func_creation = 8
    logger.info(f"Wait {wait_sec_for_func_creation} seconds for lambda "
                f"function {elisity_tag_and_state_chg_lf_name} to be deployed..")
    time.sleep(wait_sec_for_func_creation)
    update_env_vars_for_lambda_func(elisity_tag_and_state_chg_lf_name, evars)


def create_lf_for_auth_refresh():
    evars = {
        "Variables":
            {
                "eKafkaBroker": "NOT-USED",
                "retryCount": retryCountRefresh,
                "retryWaitMillis": retryWaitMillisRefresh,
                "s3Bucket": elisity_s3_bucket_name,
                "apiGwHost": api_gw_host,
                "apiGwPort": api_gw_port,
                "apiGwPath": esaas_login_path,
                "apiGwAuthRefreshPath": esaas_auth_refresh_path
            }
    }

    create_lf_util(
        lf_name=elisity_auth_refresh_lf_name,
        lf_handler="elisityTokenRefreshLF.handler",
        lf_upload_fname="elisityTokenRefreshLF.js")

    wait_sec_for_func_creation = 8
    logger.info(f"Wait {wait_sec_for_func_creation} seconds for lambda "
                f"function {elisity_auth_refresh_lf_name} to be deployed..")
    time.sleep(wait_sec_for_func_creation)
    update_env_vars_for_lambda_func(elisity_auth_refresh_lf_name, evars)


def create_lf_for_eni_tag():
    evars = {
        "Variables":
            {
                "retryCount": retryCount,
                "retryWaitMillis": retryWaitMillis
            }
    }
    create_lf_util(
        lf_name=elisity_eni_tag_create_lf_name,
        lf_handler="tagEniESaaS.tag_handler",
        lf_upload_fname="tagEniESaaS.py",
        lf_run_time="python3.7")

    wait_sec_for_func_creation = 8
    logger.info(f"Wait {wait_sec_for_func_creation} seconds for lambda "
                f"function {elisity_eni_tag_create_lf_name} to be deployed..")
    time.sleep(wait_sec_for_func_creation)
    update_env_vars_for_lambda_func(elisity_eni_tag_create_lf_name, evars)


def remove_function_code_from_local_dir():
    logger.info(f"Removing lamda function code 'tagEniESaaS.py' from {build_dir}")
    try:
        for p in Path(build_dir).glob("tagEniESaaS.py"):
            p.unlink()
    except Exception as e:
        logger.warning(f"Exception {e} while cleaning tagEniESaaS.py files")

    logger.info(f"Removing lamda function zip 'tagEniESaaS.zip' from {build_dir}")
    try:
        for p in Path(build_dir).glob("tagEniESaaS.zip"):
            p.unlink()
    except Exception as e:
        logger.warning(f"Exception {e} while cleaning tagEniESaaS.zip files")

    logger.info(f"Removing lamda js-function code from {build_dir}")
    try:
        for p in Path(build_dir).glob("elisity*.js"):
            p.unlink()
    except Exception as e:
        logger.warning(f"Exception {e} while cleaning js files from {build_dir}")

    logger.info(f"Removing lamda zip files from {build_dir}")
    try:
        for p in Path(build_dir).glob("elisity*.zip"):
            p.unlink()
    except Exception as e:
        logger.warning(f"Exception {e} while cleaning elisity*.zip files from {build_dir}")
    logger.info("Done cleaning up local dir")


def configure_and_create_all_lambda_functions():
    # get_lambda_function_code()   # Moved to the  start of script to ensure pre-requisites
    create_lambda_execution_role()
    create_lf_for_auth_refresh()
    create_lf_for_appsvc()
    create_lf_for_eni_tag()
    #remove_function_code_from_local_dir()   #Removed to support concurrent deploys


def create_event_source_mapping(event_source_arn, func_name):
    # Needed when cloud-trail events are used
    lambda_client = get_assumed_role_client('lambda')

    lambda_client.create_event_source_mapping_ext(
        EventSourceArn=event_source_arn,
        FunctionName=func_name,
        Enabled=True)

    logger.info(f"Event-Source-Mapping SUCCESS {event_source_arn} <=> {func_name}")


def add_trigger_to_lambad_func(func_name, rule_arn, rule_name):
    logger.info(f"Going to add trigger to Func {func_name} <- {rule_name}")
    lambda_client = get_assumed_role_client('lambda')
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


def put_target(ev_client, rule_name, lambda_fn_arn, lambda_fn_name, target_id="1"):
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


def create_rule(ev_client, rule_name, events, role_arn, lambda_fn_arn, lambda_fn_name):
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

    add_trigger_to_lambad_func(lambda_fn_name, rule_arn, rule_name)
    put_target(ev_client, rule_name, lambda_fn_arn, lambda_fn_name)
    return rule_arn


def create_scheduled_rule(ev_client, rule_name, sch_expr, role_arn, lambda_fn_arn, lambda_fn_name):
    logger.info(f"Going to create RULE {rule_name}")

    if tokenRefreshRateMinutes == 1:
        sch_expr = sch_expr.reaplce('minutes', 'minute')

    try:
        response = ev_client.put_rule(
            Name=rule_name,
            ScheduleExpression=sch_expr,
            State='ENABLED',
            RoleArn=role_arn
        )
        logger.info(f"Create Rule SUCCESS - {rule_name}")
        rule_arn = response['RuleArn']
    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"create rule: {ecode} Exception {rule_name}")
        raise Exception(e)

    add_trigger_to_lambad_func(lambda_fn_name, rule_arn, rule_name)
    put_target(ev_client, rule_name, lambda_fn_arn, lambda_fn_name)


def create_cloudwatch_rules_for_lambda():
    logger.info("Going to create ALL Cloud Watch Rules for Lambda")
    events_client = get_assumed_role_client('events')

    # Tag Changes Rule
    rule_arn_for_tag_chg_rule = create_rule(
        ev_client=events_client,
        rule_name=elisity_tag_chg_rule_name,
        role_arn=f"arn:aws:iam::{account_id}:role/{elisity_lambda_exec_role_name}",
        lambda_fn_arn=f"arn:aws:lambda:{aws_region}:{account_id}:function:{elisity_tag_and_state_chg_lf_name}",
        lambda_fn_name=elisity_tag_and_state_chg_lf_name,
        events="""
                 {
                      "source": [ "aws.tag" ],
                      "detail-type": [ "Tag Change on Resource" ],
                      "detail": {
                        "service": [ "ec2" ],
                        "resource-type": [ "instance" ]
                      }
                 }
                 """.strip()
    )

    # Second function that needs to get invoked on the above Tag Changes
    # Special case of one-rule calling two-functions.
    # Just have to call add_trigger() to l_function and put_target() to cw_rule
    # Make sure to match the Id when removing targets

    add_trigger_to_lambad_func(
        func_name=elisity_eni_tag_create_lf_name,
        rule_arn=rule_arn_for_tag_chg_rule,
        rule_name=elisity_tag_chg_rule_name)

    put_target(
        ev_client=events_client,
        rule_name=elisity_tag_chg_rule_name,
        lambda_fn_arn=f"arn:aws:lambda:{aws_region}:{account_id}:function:{elisity_eni_tag_create_lf_name}",
        lambda_fn_name=elisity_eni_tag_create_lf_name,
        target_id="2")

    create_rule(
        ev_client=events_client,
        rule_name=elisity_state_chg_rule_name,
        role_arn=f"arn:aws:iam::{account_id}:role/{elisity_lambda_exec_role_name}",
        lambda_fn_arn=f"arn:aws:lambda:{aws_region}:{account_id}:function:{elisity_tag_and_state_chg_lf_name}",
        lambda_fn_name=elisity_tag_and_state_chg_lf_name,
        events="""
                 {
                      "source": [ "aws.ec2" ],
                      "detail-type": [ "EC2 Instance State-change Notification" ],
                      "detail": { "state": [ "running", "stopping", "shutting-down", "terminated" ]  }
                 }
                 """.strip()
    )

    create_scheduled_rule(
        ev_client=events_client,
        rule_name=elisity_auth_refresh_rule_name,
        role_arn=f"arn:aws:iam::{account_id}:role/{elisity_lambda_exec_role_name}",
        lambda_fn_arn=f"arn:aws:lambda:{aws_region}:{account_id}:function:{elisity_auth_refresh_lf_name}",
        lambda_fn_name=elisity_auth_refresh_lf_name,
        sch_expr=f"rate({tokenRefreshRateMinutes} minutes)"  # refresh auth token every X minutes
    )


def create_bucket(bucket_name):
    logger.info("Going to create s3 bucket")
    s3_client = get_assumed_role_client('s3')
    # noinspection PyUnusedLocal
    try:
        s3_client.head_bucket(Bucket=bucket_name)
        logger.info(f"S3 Bucket {bucket_name} already exists")
        return
    except ClientError as e:
        logger.info(f"S3 Bucket {bucket_name} - has to be created")

    try:
        if aws_region == 'us-east-1':
            s3_client.create_bucket(
                Bucket=bucket_name,
            )
        else:
            s3_client.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={
                    'LocationConstraint': aws_region
                }
            )
        logger.info(f"S3 Bucket {bucket_name} creation SUCCESS")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"create s3 bucket: {ecode} Exception {bucket_name}")
        raise Exception(e)


def create_bucket_policy():
    logger.info("Going to create S3 Bucket policy")
    s3_client = get_assumed_role_client('s3')

    bucket_policy_doc = """
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AWSCloudTrailAclCheck20150319",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudtrail.amazonaws.com"
                },
                "Action": "s3:GetBucketAcl",
                "Resource": "arn:aws:s3:::<BUCKET_NAME>"
            },
            {
                "Sid": "AWSCloudTrailWrite20150319",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudtrail.amazonaws.com"
                },
                "Action": "s3:PutObject",
                "Resource": "arn:aws:s3:::<BUCKET_NAME>/AWSLogs/<ACCOUNT_ID>/*",
                "Condition": {
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control"
                    }
                }
            },
            {
                "Sid": "AllowForLambda",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::<ACCOUNT_ID>:role/<ELISITY_LAMBDA_EXEC_ROLE>"
                },
                "Action": "s3:*",
                "Resource": [
                    "arn:aws:s3:::<BUCKET_NAME>",
                    "arn:aws:s3:::<BUCKET_NAME>/*"
                ]
            }
        ]
    }
    """.strip()
    bucket_policy_doc = bucket_policy_doc \
        .replace('<BUCKET_NAME>', elisity_s3_bucket_name) \
        .replace('<ACCOUNT_ID>', account_id) \
        .replace('<ELISITY_LAMBDA_EXEC_ROLE>', elisity_lambda_exec_role_name)

    s3_client.put_bucket_policy(
        Bucket=elisity_s3_bucket_name,
        Policy=bucket_policy_doc
    )
    logger.info("create_bucket_policy - SUCCESS")


def create_lambda_cred_file():
    logger.info("Going to create lambda cred file.")

    lambda_pwd = os.environ.get('LAMBDA_PWD')
    if lambda_pwd is None:
        raise Exception("Lambda password (LAMBDA_PWD) is not available")

    lc_dir = "./.lambda"
    if not (os.path.exists(lc_dir) and os.path.isdir(lc_dir)):
        try:
            os.mkdir(lc_dir)
            logger.info(f"Successfully created the directory {lc_dir}")
        except OSError as e:
            logger.error(f"Creation of the directory %s failed{lc_dir}")
            raise Exception(e)

    lc_file = "./.lambda/.lambda_cred"
    data = '{"uid": "lambda", "pwd": "<LPWD>"}'.replace('<LPWD>', lambda_pwd)

    if os.path.exists(lc_file):
        logger.info("Lambda cred file already exists, skipping.")
        return

    with open(lc_file, 'w') as file:
        file.write(data)
    logger.info("Lambda cred file created.")


def insert_lambda_user_into_s3():
    logger.info(f"Going to Write cred to S3 - "
                f"Bucket: {elisity_s3_bucket_name} "
                f"Key: {elisity_cred_s3_object_key}")

    create_lambda_cred_file()

    session = get_assumed_role_session()
    s3_client = session.resource('s3', region_name=aws_region)
    try:
        file_to_upload = '.lambda/.lambda_cred'
        s3_client.Object(
            elisity_s3_bucket_name,
            elisity_cred_s3_object_key).put(Body=open(file_to_upload, 'rb'))

        logger.info(f"Write cred to S3 - SUCCESS - "
                    f"Bucket: {elisity_s3_bucket_name} "
                    f"Key: {elisity_cred_s3_object_key}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        logger.error(f"Unable to write cred into S3. EXCEPTION {ecode} - "
                     f"Bucket: {elisity_s3_bucket_name} "
                     f"Key: {elisity_cred_s3_object_key}")
        raise Exception(e)
    finally:
        remove_cred_file_from_local_dir()


def remove_cred_file_from_local_dir():
    logger.info("Not removing cred file from local dir")
    '''
    logger.info("Removing cred file from local dir")
    lc_dir = "./.lambda"
    lc_file = "./.lambda/.lambda_cred"
    if os.path.exists(lc_dir) and os.path.isdir(lc_dir):
        try:
            if os.path.exists(lc_file):
                os.remove(lc_file)
            os.rmdir(lc_dir)
            logger.info(f"Successfully removed the directory {lc_dir}")
        except OSError as e:
            logger.error(f"Removeal of the directory %s failed{lc_dir}. Exception {e}")
    '''


# noinspection DuplicatedCode
def clear_existing_setup():
    logger.info("Going to clean-up existing rules, policies, roles, lambda-functions, etc.")

    session = get_assumed_role_session()
    lambda_client = session.client('lambda', region_name=aws_region)

    logger.info(f"Going to remove trigger {elisity_auth_refresh_rule_name} "
                f"from lambda function {elisity_auth_refresh_lf_name}")
    try:
        lambda_client.remove_permission(
            FunctionName=elisity_auth_refresh_lf_name,
            StatementId=f"{elisity_auth_refresh_rule_name}-Event"
        )
        logger.info(f"REMOVE trigger SUCCESS {elisity_auth_refresh_rule_name} "
                    f"from lambda function {elisity_auth_refresh_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(f"No need to REMOVE trigger - {elisity_auth_refresh_rule_name} "
                        f"from lambda function {elisity_auth_refresh_lf_name}")
        else:
            logger.error(f"REMOVE trigger EXCEPTION {ecode} - {elisity_auth_refresh_rule_name} "
                         f"from lambda function {elisity_auth_refresh_lf_name}")
            raise Exception(e)

    logger.info(f"Going to remove trigger {elisity_state_chg_rule_name} "
                f"from lambda function {elisity_tag_and_state_chg_lf_name}")
    try:
        lambda_client.remove_permission(
            FunctionName=elisity_tag_and_state_chg_lf_name,
            StatementId=f"{elisity_state_chg_rule_name}-Event"
        )
        logger.info(f"REMOVE trigger SUCCESS {elisity_state_chg_rule_name} "
                    f"from lambda function {elisity_tag_and_state_chg_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(f"No need to REMOVE trigger - {elisity_state_chg_rule_name} "
                        f"from lambda function {elisity_tag_and_state_chg_lf_name}")
        else:
            logger.error(f"REMOVE trigger EXCEPTION {ecode} - {elisity_state_chg_rule_name} "
                         f"from lambda function {elisity_tag_and_state_chg_lf_name}")
            raise Exception(e)

    logger.info(f"Going to remove trigger {elisity_tag_chg_rule_name} "
                f"from lambda function {elisity_tag_and_state_chg_lf_name}")
    try:
        lambda_client.remove_permission(
            FunctionName=elisity_tag_and_state_chg_lf_name,
            StatementId=f"{elisity_tag_chg_rule_name}-Event"
        )
        logger.info(f"REMOVE trigger SUCCESS {elisity_tag_chg_rule_name} "
                    f"from lambda function {elisity_tag_and_state_chg_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(f"No need to REMOVE trigger {elisity_tag_chg_rule_name} "
                        f"from lambda function {elisity_tag_and_state_chg_lf_name}")
        else:
            logger.error(f"REMOVE trigger EXCEPTION {ecode} - {elisity_tag_chg_rule_name} "
                         f"from lambda function {elisity_tag_and_state_chg_lf_name}")
            raise Exception(e)
    # --------------------------------------------------------------------------
    logger.info(f"Going to remove trigger {elisity_tag_chg_rule_name} "
                f"from lambda function {elisity_eni_tag_create_lf_name}")
    try:
        lambda_client.remove_permission(
            FunctionName=elisity_eni_tag_create_lf_name,
            StatementId=f"{elisity_tag_chg_rule_name}-Event"
        )
        logger.info(f"REMOVE trigger SUCCESS {elisity_tag_chg_rule_name} "
                    f"from lambda function {elisity_eni_tag_create_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(f"No need to REMOVE trigger {elisity_tag_chg_rule_name} "
                        f"from lambda function {elisity_eni_tag_create_lf_name}")
        else:
            logger.error(f"REMOVE trigger EXCEPTION {ecode} - {elisity_tag_chg_rule_name} "
                         f"from lambda function {elisity_eni_tag_create_lf_name}")
            raise Exception(e)
    # --------------------------------------------------------------------------

    # cleanup role
    iam_client = session.client('iam', region_name=aws_region)
    policy_arn = f"arn:aws:iam::{account_id}:policy/{elisity_lambda_exec_policy_name}"
    logger.info(f"Going to detach policy from role {policy_arn}")
    try:
        iam_client.detach_role_policy(
            RoleName=elisity_lambda_exec_role_name,
            PolicyArn=policy_arn
        )
        logger.info(f"Detach policy SUCCESS {policy_arn}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'NoSuchEntity':
            logger.info(f"No need to detach policy {policy_arn}")
        else:
            logger.error(f"Error {ecode} while Detach policy {policy_arn}")
            raise Exception(e)
    logger.info(f"Going to delete policy from role {policy_arn}")
    try:
        iam_client.delete_policy(PolicyArn=policy_arn)
        logger.info(f"Delete policy SUCCESS {policy_arn}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'NoSuchEntity':
            logger.info(f"No need to delete policy {policy_arn}")
        else:
            logger.error(f"Error {ecode} while Delete policy {policy_arn}")
            raise Exception(e)

    logger.info(f"Going to DELETE ROLE {elisity_lambda_exec_role_name}")
    try:
        iam_client.delete_role(RoleName=elisity_lambda_exec_role_name)
        logger.info(f"Delete Role SUCCESS {elisity_lambda_exec_role_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'NoSuchEntity':
            logger.info(f"No need to delete Role {elisity_lambda_exec_role_name}")
        #elif iam_client.exceptions.EntityAlreadyExistsException:
        #    logger.warning(f"Role {elisity_lambda_exec_role_name} already exists")
        else:
            logger.error(f"Error {ecode} while Delete Role {elisity_lambda_exec_role_name}")
            raise Exception(e)

    # --- Remove targets from Rule (lambda-funcitons associated with Rule)
    logger.info(f"Going to REMOVE targets from RULE {elisity_auth_refresh_rule_name}")
    events_client = session.client('events', region_name=aws_region)
    try:
        events_client.remove_targets(
            Rule=elisity_auth_refresh_rule_name, Ids=["1"], Force=True)
        logger.info(f"Remove Target SUCCESS {elisity_auth_refresh_rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to remove target for {elisity_auth_refresh_rule_name}")
        else:
            logger.error(f"Error {ecode} while Removing Target {elisity_auth_refresh_rule_name}")
            raise Exception(e)

    logger.info(f"Going to REMOVE targets from RULE {elisity_state_chg_rule_name}")
    events_client = session.client('events', region_name=aws_region)
    try:
        events_client.remove_targets(
            Rule=elisity_state_chg_rule_name, Ids=["1"], Force=True)
        logger.info(f"Remove Target SUCCESS {elisity_state_chg_rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to remove target for {elisity_state_chg_rule_name}")
        else:
            logger.error(f"Error {ecode} while Removing Target {elisity_state_chg_rule_name}")
            raise Exception(e)

    logger.info(f"Going to REMOVE targets from RULE {elisity_tag_chg_rule_name}")
    try:
        events_client.remove_targets(
            Rule=elisity_tag_chg_rule_name, Ids=["1"], Force=True)
        logger.info(f"Remove Target SUCCESS {elisity_tag_chg_rule_name}")

    except ClientError as e:  # ResourceNotFoundException
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to remove target for {elisity_tag_chg_rule_name}")
        else:
            logger.error(f"Error {ecode} while Removing Target {elisity_tag_chg_rule_name}")
            raise Exception(e)

    # --------------------------------------------------------------------------
    # TODO:  TEST THE TARGET INDEX.... Oct-16-2019

    logger.info(f"Going to REMOVE 2nd target from RULE {elisity_tag_chg_rule_name}")
    try:
        events_client.remove_targets(
            Rule=elisity_tag_chg_rule_name, Ids=["2"], Force=True)
        logger.info(f"Remove Target SUCCESS {elisity_tag_chg_rule_name}")

    except ClientError as e:  # ResourceNotFoundException
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to remove target for {elisity_tag_chg_rule_name}")
        else:
            logger.error(f"Error {ecode} while Removing Target {elisity_tag_chg_rule_name}")
            raise Exception(e)
    # --------------------------------------------------------------------------
    logger.info(f"Going to DELETE lambda function {elisity_eni_tag_create_lf_name}")
    try:
        lambda_client.delete_function(FunctionName=elisity_eni_tag_create_lf_name)
        logger.info(f"Delete lam-func SUCCESS {elisity_eni_tag_create_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete lam-func {elisity_eni_tag_create_lf_name}")
        else:
            logger.error(f"Error {ecode} deleting lam-func {elisity_eni_tag_create_lf_name}")
            raise Exception(e)
    # ----------------------------------------------------------------------------

    logger.info(f"Going to DELETE lambda function {elisity_tag_and_state_chg_lf_name}")
    try:
        lambda_client.delete_function(FunctionName=elisity_tag_and_state_chg_lf_name)
        logger.info(f"Delete lam-func SUCCESS {elisity_tag_and_state_chg_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete lam-func {elisity_tag_and_state_chg_lf_name}")
        else:
            logger.error(f"Error {ecode} deleting lam-func {elisity_tag_and_state_chg_lf_name}")
            raise Exception(e)

    logger.info(f"Going to DELETE lambda function {elisity_auth_refresh_lf_name}")
    try:
        lambda_client.delete_function(FunctionName=elisity_auth_refresh_lf_name)
        logger.info(f"Delete lam-func SUCCESS {elisity_auth_refresh_lf_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete lam-func {elisity_auth_refresh_lf_name}")
        else:
            logger.error(f"Excetion {ecode} while deleting lam-func {elisity_auth_refresh_lf_name}")
            raise Exception(e)

    logger.info(f"Going to DELETE RULE {elisity_auth_refresh_rule_name}")
    events_client = session.client('events', region_name=aws_region)
    try:
        events_client.delete_rule(Name=elisity_auth_refresh_rule_name, Force=True)
        logger.info(f"Delete Rule SUCCESS {elisity_auth_refresh_rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete rule {elisity_auth_refresh_rule_name}")
        else:
            logger.error(f"Error {ecode} while Deleting rule {elisity_auth_refresh_rule_name}")
            raise Exception(e)

    logger.info(f"Going to DELETE RULE {elisity_state_chg_rule_name}")
    events_client = session.client('events', region_name=aws_region)
    try:
        events_client.delete_rule(Name=elisity_state_chg_rule_name, Force=True)
        logger.info(f"Delete Rule SUCCESS {elisity_state_chg_rule_name}")
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete rule {elisity_state_chg_rule_name}")
        else:
            logger.error(f"Error {ecode} while Deleting rule {elisity_state_chg_rule_name}")
            raise Exception(e)

    logger.info(f"Going to DELETE RULE {elisity_tag_chg_rule_name}")
    try:
        events_client.delete_rule(Name=elisity_tag_chg_rule_name, Force=True)
        logger.info(f"Delete Rule SUCCESS {elisity_tag_chg_rule_name}")

    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == 'ResourceNotFoundException':
            logger.info(f"No need to delete rule {elisity_tag_chg_rule_name}")
        else:
            logger.error(f"Error {ecode} while Deleting rule {elisity_tag_chg_rule_name}")
            raise Exception(e)

    logger.info("All clean-up COMPLETED\n")


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


def get_initial_auth_token():
    logger.info(f"Going to get initial Auth Token by invoking LF call")
    lambda_client = get_assumed_role_client('lambda')
    try:
        response = lambda_client.invoke(
            FunctionName=elisity_auth_refresh_lf_name,
            InvocationType='Event',
            LogType='None',
            Payload=b'{"Event": "init token"}'
        )
        logger.info(f"Get initial Auth Token LF call SUCCESS. Check execution logs in AWS. {response}")
    except ClientError as e:
        logger.error("Get initial Auth Token failed with exception {e}")
        raise Exception(e)


def deploy_in_region(region):
    global aws_region, elisity_s3_bucket_name, \
        elisity_lambda_exec_role_name, \
        elisity_lambda_exec_policy_name, \
        overwrite, \
        delete_res_only
    logger.info(f"4 delete_res_only {delete_res_only}")

    aws_region = region
    elisity_s3_bucket_name = f"{resource_prefix}-elisity-{account_id}-{region}"
    elisity_lambda_exec_role_name = f"{resource_prefix}elisityLambdaExecRole-{region}"
    elisity_lambda_exec_policy_name = f"{resource_prefix}elisityLambdaExecPolicy-{region}"
    logger.info(f"bucket name: {elisity_s3_bucket_name}")
    logger.info(f"roles name: {elisity_lambda_exec_role_name}")
    logger.info(f"policy name: {elisity_lambda_exec_policy_name}")

    if not overwrite and check_lambda_exists():
        logger.info(f"Lambda function already exists in {aws_region} and overwrite is disabled, skipping deployment.")
        return


    clear_existing_setup()
    logger.info(f"5 delete_res_only {delete_res_only}")
    if delete_res_only:
        return
    configure_and_create_all_lambda_functions()
    create_cloudwatch_rules_for_lambda()
    create_bucket(elisity_s3_bucket_name)
    create_bucket_policy()
    insert_lambda_user_into_s3()
    get_initial_auth_token()


def check_lambda_exists():
    logger.info(f"Checking if lambda function already exists: {elisity_tag_and_state_chg_lf_name}")

    session = get_assumed_role_session()
    lambda_client = session.client('lambda', region_name=aws_region)
    try:
        response = lambda_client.get_function(FunctionName=elisity_tag_and_state_chg_lf_name)
    except ClientError as e:
        ecode = e.response['Error']['Code']
        if ecode == "ResourceNotFoundException":
            logger.info(f"Lambda fn not found: {elisity_tag_and_state_chg_lf_name}. This should mean all other lambda resources do not exist.")
            return False
    return True




def init(options):
    global aws_profile, account_id, profile_id, api_gw_host, api_gw_port, gw_addr, role_arn, external_id,\
        resource_prefix, zip_file_dir, \
        elisity_s3_bucket_name, \
        elisity_lambda_exec_role_name, \
        elisity_lambda_exec_policy_name, \
        elisity_tag_chg_rule_name, \
        elisity_state_chg_rule_name, \
        elisity_tag_and_state_chg_lf_name, \
        elisity_auth_refresh_lf_name, \
        elisity_auth_refresh_rule_name, \
        tokenRefreshRateMinutes, \
        delete_res_only, \
        elisity_eni_tag_create_lf_name, \
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

    #elisity_s3_bucket_name = f"{resource_prefix}-elisity-{account_id}"  # NO underscore, period, or uppercase. len <=63
    #elisity_lambda_exec_role_name = f"{resource_prefix}elisityLambdaExecRole"
    #elisity_lambda_exec_policy_name = f"{resource_prefix}elisityLambdaExecPolicy"
    elisity_tag_chg_rule_name = f"{resource_prefix}elisityTagChgRule"
    elisity_state_chg_rule_name = f"{resource_prefix}elisityStateChgRule"
    elisity_tag_and_state_chg_lf_name = f"{resource_prefix}elisityTagAndStateChgLF"
    elisity_auth_refresh_lf_name = f"{resource_prefix}elisityAuthRefreshLF"
    elisity_auth_refresh_rule_name = f"{resource_prefix}elisityAuthRefreshRule"
    elisity_eni_tag_create_lf_name = f"{resource_prefix}elisityEniTagCreateLF"

    if options['role_arn'] is not None:
        role_arn = options['role_arn']
    else:
        raise Exception("Role ARN is required.")

    if options['external_id'] is not None:
        external_id = options['external_id']
    else:
        raise Exception("ExternalId is required.")

    return options


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


def deploy():
    options = get_options()
    init(options)
    logger.info(f"2 delete_res_only {delete_res_only}")

    # Ensure lambda password is set in env variable
    # For a delete-only run, password is not required
    if not delete_res_only:
        lambda_pwd = os.environ.get('LAMBDA_PWD')
        if lambda_pwd is None:
            raise Exception("Lambda password (LAMBDA_PWD) for API-GW is not available")

        get_lambda_function_code()
    logger.info(f"3 delete_res_only {delete_res_only}")

    if options['regions'] is not None:
        for region in options['regions']:
            deploy_in_region(region)


def main():
    try:
        deploy()
    except Exception as e:
        raise Exception(e)
    finally:
        remove_cred_file_from_local_dir()


if __name__ == '__main__':
    main()
