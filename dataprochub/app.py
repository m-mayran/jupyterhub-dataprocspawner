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

""" Replaces default JupyterHub.app to handle redirects. """

from jupyterhub.app import JupyterHub
from jupyterhub.handlers.base import UserUrlHandler
from jupyterhub import handlers, apihandlers
from jupyterhub.handlers.static import LogoHandler
import re

class DataprocHubUserUrlHandler(UserUrlHandler):
  """ Extends UserUrlHandler to redirect user once spawn is done. """

  async def _redirect_to_user_server(self, user, spawner):
    self.statsd.incr('redirects.user_after_login')
    redirect_url = user.spawners[spawner.name].component_gateway_url
    self.log.info(f'# Redirecting to notebook at {redirect_url}.')
    self.redirect(redirect_url)

class DataprocHub(JupyterHub):
  """ Extends JupyterHub mainly to handle redirect vs proxy. """

  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)

    self.new_user_handler = (
      r'/user/(?P<user_name>[^/]+)(?P<user_path>/.*)?',
      DataprocHubUserUrlHandler,
    )

    self.new_user_handler_prefixed = self.add_url_prefix(
        self.hub_prefix, [self.new_user_handler])[0]

    self.regex_to_change = {
      r'%s(user|services)/([^/]+)' % self.base_url: r'%s(services)/([^/]+)' % self.base_url
    }

    self.handler_to_change = {
      self.new_user_handler_prefixed[0]: self.new_user_handler_prefixed[1]
    }

  def init_handlers(self):
    """ Modifies the default app handlers.

    Modifies the default behavior of JupyterHub user URL handler to use a custom
    handler and allow Dataproc Hub to do redirect instead of proxying.

    Handlers are tuples of the form (regex_path, handler_class).

    Order of the element in the handlers list matters!!!
    """
    super().init_handlers()

    for idx, h in enumerate(self.handlers):
      h_regex = h[0]
      h_class = h[1]

      if h_regex in self.regex_to_change:
        self.handlers[idx] = (self.regex_to_change[h_regex], h_class)

      if h_regex in self.handler_to_change:
        self.handlers[idx] = (h_regex, self.handler_to_change[h_regex])

    self.handlers.append(self.new_user_handler)
    self.log.debug(self.handlers)

main = DataprocHub.launch_instance

if __name__ == '__main__':
  main()
