#!/bin/sh
#josh@elisity.com
#Starts the lambda deploy python flask service
export SERVICE_ROOT="/srv/aws_lambda_deploy/aws_lambda_deploy"

pipenv run gunicorn \
  --ssl-version TLSv1_2 \
  --certfile=/data/certs/tls.crt \
  --keyfile=/data/certs/tls.key \
  lambda_rest_api:flask_app
