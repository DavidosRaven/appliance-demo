set -x
set -e

# we assume that we have a Raspbian system running
# with a user named rdb 

# setup wifi properly
sudo raspi-config nonint do_wifi_country IL
sudo rfkill unblock wifi

sudo swapoff /var/swap
sudo dd if=/dev/zero of=/var/swap count=8 bs=128M
sudo mkswap /var/swap
sudo chmod 0600 /var/swap
sudo swapon /var/swap

# install node.js from nodesource (raspbian has only node 12)
curl -fsSL https://deb.nodesource.com/setup_21.x | sudo -E bash - && sudo apt-get install -y nodejs

# install nginx and dnsmasq
sudo apt-get install -y nginx dnsmasq dhcpcd
sudo dpkg -i ravendb.deb
rm  ravendb.deb

sudo mkdir -p /var/lib/ravendb/data/Databases
sudo mv raspberrypi.stackexchange.com /var/lib/ravendb/data/Databases/raspberrypi.stackexchange.com
sudo chown --recursive ravendb:ravendb /var/lib/ravendb/data/Databases
sudo mv settings.json /etc/ravendb/settings.json
sudo chown root:ravendb /etc/ravendb/settings.json
sudo systemctl restart ravendb

# setup the web app users
getent group node-apps || sudo groupadd node-apps
NODE_GID=$(getent group node-apps | cut -d ':' -f 3)
getent passwd hugin-web || sudo adduser --disabled-login --disabled-password --system \
  --home /var/lib/hugin-web --no-create-home --quiet --gid "$NODE_GID" hugin-web

cd ~/web
npm install
cd ~/
sudo mv ./web /usr/lib/hugin-web
sudo chown --recursive root:node-apps /usr/lib/hugin-web
sudo mv hugin-web.service /etc/systemd/system/hugin-web.service
sudo systemctl enable hugin-web


curl 'http://127.0.0.1:8080/admin/databases?name=raspberrypi.stackexchange.com&replicationFactor=1' \
  -X 'PUT' --data-raw '{"DatabaseName":"raspberrypi.stackexchange.com"}'


sudo systemctl start hugin-web


# configuration of the system
sudo mv etc.wpa_supplicant.wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
sudo mv etc.nginx.sites-available.default /etc/nginx/sites-available/default
sudo mv etc.dhcpcd.conf /etc/dhcpcd.conf
sudo mv etc.dnsmasq.conf /etc/dnsmasq.conf

sudo sed -i 's/#DNSMASQ_EXCEPT="lo"/DNSMASQ_EXCEPT="lo"/g' /etc/default/dnsmasq
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf 

# restart services and prepare...
sudo systemctl stop wpa_supplicant
sudo systemctl mask wpa_supplicant

sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq
sudo service dhcpcd restart
sudo wpa_cli -i wlan0 reconfigure
sudo nginx -s reload

rm * # cleanup directoy

echo "Ready ..."