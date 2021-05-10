import boto3
import logging
logger = logging.getLogger()
logger.setLevel(logging.ERROR)
ec2 = boto3.resource('ec2', region_name="us-east-2")

def tag_handler(event, context):
    base = ec2.instances.all()
    for instance in base:
#Tag the Network Interfaces with label tags
        for itag in instance.tags:
            if(itag['Value']=='ESI'):
                for eni in instance.network_interfaces:
                    tag = eni.create_tags(Tags=[{'Key': 'ElisityInfraType', 'Value': 'ESNI'}])
                    print("[INFO]: " + str(tag))

