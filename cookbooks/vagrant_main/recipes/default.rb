include_recipe "apt"
include_recipe "build-essential"
include_recipe "git"

# Configure Ubuntu to use Ondřej Surý's PHP 5.4 PPA.
# We use PHP 5.4, since that is the most common version of PHP used by shared
# web hosts and is the minimum version required by Laravel 4.2 and later.
apt_respository "php5-oldstable" do
  uri "https://launchpad.net/~ondrej/+archive/ubuntu/php5-oldstable"
  distribution "trusty"
  components ["main"]
  keyserver "keyserver.ubuntu.com"
  key "E5267A6C"
end

include_recipe "apache2"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_ssl"
include_recipe "mysql::server"
include_recipe "php"
include_recipe "php::module_mysql"
include_recipe "php::module_apc"
include_recipe "php::module_curl"
include_recipe "apache2::mod_php5"
include_recipe "composer"
include_recipe "php-box"

# Install packages
%w{ python-software-properties debconf vim screen tmux mc curl make g++ libsqlite3-dev graphviz libxml2-utils lynx links}.each do |a_package|
  package a_package
end

# Install ruby gems
gem_package "rake" do
  version "0.8.7"
end

# Generate selfsigned ssl
execute "make-ssl-cert" do
  command "make-ssl-cert generate-default-snakeoil --force-overwrite"
  ignore_failure true
  action :nothing
end

# Initialize sites data bag
sites = []
begin
  sites = data_bag("sites")
rescue
  puts "Unable to load sites data bag."
end

# Configure sites
sites.each do |name|
  site = data_bag_item("sites", name)

  # Add site to apache config
  web_app site["host"] do
    template "sites.conf.erb"
    server_name site["host"]
    server_aliases site["aliases"]
    server_include site["include"]
    docroot site["docroot"]?site["docroot"]:"/vagrant/public/#{site["host"]}"
  end

   # Add site info in /etc/hosts
   bash "hosts" do
     code "echo 127.0.0.1 #{site["host"]} #{site["aliases"].join(' ')} >> /etc/hosts"
   end
end

# Disable default site
apache_site "default" do
  enable false
end

# Install phpmyadmin
cookbook_file "/tmp/phpmyadmin.deb.conf" do
  source "phpmyadmin.deb.conf"
end
bash "debconf_for_phpmyadmin" do
  code "debconf-set-selections /tmp/phpmyadmin.deb.conf"
end
package "phpmyadmin"

# Install Xdebug
php_pear "xdebug" do
  action :install
end
template "#{node['php']['ext_conf_dir']}/xdebug.ini" do
  source "xdebug.ini.erb"
  owner "root"
  group "root"
  mode "0644"
  action :create
  notifies :restart, resources("service[apache2]"), :delayed
end

# Install php-xsl
package "php5-xsl" do
  action :install
end

# Install php-mcrypt
package "php5-mcrypt" do
  action :install
end

# Fixing deprecated php comments style in ini files
bash "deploy" do
  code "sudo perl -pi -e 's/(\s*)#/$1;/' /etc/php5/cli/conf.d/*ini"
  notifies :restart, resources("service[apache2]"), :delayed
end
