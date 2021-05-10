import multiprocessing
from datetime import datetime


timeout = 300
bind = "0.0.0.0:9443"
workers = 4
date_time = datetime.now().strftime("%m_%d_%Y_%H_%M_%S")
# errorlog = f"{date_time}_lambdadeploy.log"
capture_output = False # True
