# frozen_string_literal: true
#
# Cookbook:: postgresql
# Resource:: server_install
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include PostgresqlCookbook::Helpers

property :version,           String, default: '9.6'
property :setup_repo,        [true, false], default: true
property :data_directory,    String, default: lazy { data_dir }
property :config_directory,  String, default: lazy { conf_dir }
property :hba_file,          String, default: lazy { "#{conf_dir}/pg_hba.conf" }
property :ident_file,        String, default: lazy { "#{conf_dir}/pg_ident.conf" }
property :external_pid_file, String, default: lazy { "/var/run/postgresql/#{version}-main.pid" }
property :password,          [String, nil], default: 'generate' # Set to nil if we do not want to set a password
property :port,              Integer, default: 5432
property :cookbook,          String, default: 'postgresql'
property :initdb_locale,     String

# Connection preferences
property :user,     String, default: 'postgres'
property :database, String
property :host,     [String, nil]

action :install do
  postgresql_client_install 'Install PostgreSQL Client' do
    version new_resource.version
    setup_repo new_resource.setup_repo
  end
  package server_pkg_name
end

action :create do
  node.run_state['postgresql'] ||= {}
  node.run_state['postgresql']['version'] = new_resource.version
  node.run_state['postgresql']['data_dir'] = new_resource.data_directory
  node.run_state['postgresql']['conf_dir'] = new_resource.config_directory

  directory new_resource.data_directory do
    owner 'postgres'
    group 'postgres'
    mode '0700'
    recursive true
    action :create
  end

  execute 'init_db' do
    command rhel_init_db_command(new_resource)
    user new_resource.user
    not_if { initialized? }
    only_if { platform_family?('rhel', 'fedora', 'amazon') }
  end

  # We use to use find_resource here.
  # But that required the user to do the same in their recipe.
  # This also seemed to never trigger notifications, therefore requiring a log resource
  # to notify the enable/start on the service, which always fires (Check v7.0 tag for more)
  service 'postgresql' do
    service_name platform_service_name(new_resource.version)
    case node['platform_family']
    when 'rhel', 'fedora', 'amazon'
      svc_override_dir = '/etc/systemd/system'
      template "#{svc_override_dir}/#{platform_service_name(new_resource.version)}.service" do
        cookbook new_resource.cookbook
        source 'postgresql.service.erb'
        owner 'root'
        group 'root'
        mode '0644'
        variables(
          svc_name: platform_service_name(new_resource.version),
          port: new_resource.port,
          data_dir: new_resource.data_dir
        )
      end
    end
    supports restart: true, status: true, reload: true
    action [:enable, :start]
  end

  # Generate a random password or set it as per new_resource.password.
  bash 'generate-postgres-password' do
    user 'postgres'
    code alter_role_sql(new_resource)
    not_if { user_has_password?(new_resource) }
    not_if { new_resource.password.nil? }
  end
end

action_class do
  include PostgresqlCookbook::Helpers
end
