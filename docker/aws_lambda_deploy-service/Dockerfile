FROM python:3.6.13-alpine3.13

# Install required software.
RUN pip install pipenv

# Create service user and service directory, then use them going forward.
RUN addgroup -g 1000 svc && \
    adduser -u 1000 -h /srv/aws_lambda_deploy -D -G svc svc && \
    mkdir -p /srv/aws_lambda_deploy/aws_lambda_deploy /srv/aws_lambda_deploy/aws_lambda_function && \
    chown -R svc:svc /srv/aws_lambda_deploy
USER svc:svc
WORKDIR /srv/aws_lambda_deploy/aws_lambda_deploy

# Install application dependencies before source code (this is a docker image optimization technique)
COPY --chown=svc:svc aws_lambda_deploy/Pipfile* /srv/aws_lambda_deploy/aws_lambda_deploy/Pipfile
RUN pipenv install

# Copy the rest of the source code into the service directory.
COPY --chown=svc:svc aws_lambda_deploy/* /srv/aws_lambda_deploy/aws_lambda_deploy/
COPY --chown=svc:svc aws_lambda_function/* /srv/aws_lambda_deploy/aws_lambda_function/
COPY --chown=svc:svc *.py /srv/aws_lambda_deploy/

ENTRYPOINT ["/srv/aws_lambda_deploy/aws_lambda_deploy/start_service.sh"]

LABEL maintainer="Josh Tai <josh@elisity.com>, Joseph Khoobyar <joe@duplocloud.net>"
LABEL app="elisity.com/aws_lambda_deploy"
