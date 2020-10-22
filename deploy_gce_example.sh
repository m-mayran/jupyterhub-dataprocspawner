#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Usage: bash deploy_gce_example.sh <PROJECT_ID> <VM_NAME>

# RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
# RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
# RUN apt-get update && apt-get install -y \
#     apt-transport-https \
#     ca-certificates \
#     gnupg \
#     google-cloud-sdk \
#     vim

PROJECT_ID=$1
VM_NAME=$2
CONFIGS_LOCATION=$3
DOCKER_IMAGE="gcr.io/${PROJECT_ID}/dataprocspawner:cg"

cat <<EOT > Dockerfile
FROM jupyterhub/jupyterhub

RUN pip install jupyterhub-dummyauthenticator

COPY jupyterhub_config.py .

COPY . dataprocspawner/
RUN cd dataprocspawner && pip install .

COPY templates /etc/jupyterhub/templates

ENTRYPOINT ["jupyterhub"]
EOT

cat <<EOT > jupyterhub_config.py
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

c.JupyterHub.authenticator_class = 'dummyauthenticator.DummyAuthenticator'
c.JupyterHub.spawner_class = 'dataprocspawner.DataprocSpawner'
# The port that the spawned notebook listens on for the hub to connect
c.Spawner.port = 12345

import socket

# Have JupyterHub listen on all interfaces
c.JupyterHub.hub_ip = '0.0.0.0'
# The IP address that other services should use to connect to the hub
c.JupyterHub.hub_connect_ip = socket.gethostbyname(socket.gethostname())

c.DataprocSpawner.dataproc_configs = "${CONFIGS_LOCATION}"
c.DataprocSpawner.dataproc_locations_list = "b,c"

# TODO(mayran): Move the handler into Python code
# and properly log Component Gateway being None.
from jupyterhub.handlers.base import BaseHandler
from tornado.web import authenticated

class RedirectComponentGatewayHandler(BaseHandler):
  @authenticated
  async def get(self, user_name='', user_path=''):
    next_url = self.current_user.spawner.component_gateway_url
    if next_url:
      self.redirect(next_url)
    self.redirect('/404')
    
c.JupyterHub.extra_handlers = [
  (r"/redirect-component-gateway(/*)", RedirectComponentGatewayHandler),
]
c.JupyterHub.template_paths = ['/etc/jupyterhub/templates']
EOT


gcloud --project "${PROJECT_ID}" builds submit -t "${DOCKER_IMAGE}" .

gcloud beta compute instances create-with-container "${VM_NAME}" \
  --project "${PROJECT_ID}" \
  --container-image="${DOCKER_IMAGE}" \
  --container-arg="--DataprocSpawner.project=${PROJECT_ID}" \
  --scopes=cloud-platform \
  --zone us-central1-a

gcloud compute instances describe "${VM_NAME}" \
  --project "${PROJECT_ID}" \
  --zone us-central1-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'

# Clean up
rm Dockerfile
rm jupyterhub_config.py
