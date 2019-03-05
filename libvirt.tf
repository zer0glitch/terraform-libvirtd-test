# instance the provider
provider "libvirt" {
  #uri = "test+tcp://172.26.14.7/system"
  #uri = "qemu://172.26.14.7/system?no_verify=1"
  uri = "qemu+tcp://172.26.14.7/system"
  #uri = "qemu+ssh://172.26.14.7/system"
  #uri = "qemu:///system"
}

#resource "libvirt_network" "libvirt_bridge" {
#  name = "bridge"
#  mode = "bridge"
#  bridge = "virbr0"
#}

# We fetch the latest centos release image from their mirrors
resource "libvirt_volume" "centos-qcow2" {
  name   = "centos-qcow2"
  pool   = "default"
  source = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1811.qcow2"
  format = "qcow2"
}

# We fetch the latest ubuntu release image from their mirrors
#resource "libvirt_volume" "ubuntu-qcow2" {
#  name   = "ubuntu-qcow2"
#  pool   = "default"
#  source = "https://cloud-images.ubuntu.com/releases/xenial/release/ubuntu-16.04-server-cloudimg-amd64-disk1.img"
#  format = "qcow2"
#}

data "template_file" "user_data" {
  template = "${file("${path.module}/cloud_init.cfg")}"
}

data "template_file" "network_config" {
  template = "${file("${path.module}/network_config.cfg")}"
}

#data "template_file" "network_config" {
#  template = "${file("${path.module}/network_data.json")}"
#}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = "${data.template_file.user_data.rendered}"
  network_config = "${data.template_file.network_config.rendered}"
}

#resource "libvirt_network" "default" {
#  name = "default"
#  label = "eno1"
#  ipv4_gateway = "172.26.14.1"
#  ipv4_address = "172.26.14.60"
#  ipv4_prefix_length = "24"
#}

# Create the machine
resource "libvirt_domain" "domain-centos" {
  name   = "centos-terraform"
  memory = "512"
  vcpu   = 1

  cloudinit = "${libvirt_cloudinit_disk.commoninit.id}"

#      network_interface.#:              "1"
#      network_interface.0.addresses.#:  <computed>
#      network_interface.0.hostname:     <computed>
#      network_interface.0.mac:          <computed>
#      network_interface.0.network_id:   <computed>
#      network_interface.0.network_name: "default"



  network_interface {
    network_name = "default"
    wait_for_lease = "true"
  }

#    <interface type='network'>
#      <mac address='9e:8d:5e:e5:fc:49'/>
#      <source network='default'/>
#      <model type='virtio'/>
#      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
#    </interface>


  network_interface {
    bridge = "br0"
    #network_id = "eth1"
    #network_name = "eth1"
    mac    = "52:54:00:b2:2f:86"
    addresses = ["172.26.14.60/24"]
    hostname = "test.zeroglitch.com"
  }

#    <interface type='bridge'>
#      <mac address='52:54:00:cd:58:c1'/>
#      <source bridge='br0'/>
#      <model type='virtio'/>
#      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
#    </interface>


  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = "${libvirt_volume.centos-qcow2.id}"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }


#  provisioner "local-exec" {
#    command = "echo ${data}"
#  }


  provisioner "file" {
    source      = "./acs.repo"
    destination = "/etc/yum.repos.d/acs.repo"

    connection {
      host     = "${self.network_interface.0.addresses.0}"
      type     = "ssh"
      user     = "root"
      password = "junker"
      agent = "false"
    }

  }
  provisioner "file" {
    source      = "./eth1.cfg"
    destination = "/etc/sysconfig/network-scripts/ifcfg-eth1"

    connection {
      host     = "${self.network_interface.0.addresses.0}"
      type     = "ssh"
      user     = "root"
      password = "junker"
      agent = "false"
    }

  }
  provisioner "remote-exec" {

    inline = [
              "systemctl restart network",
              "yum install -y ansible git firewalld",
              "cd /opt && git clone https://github.com/zer0glitch/terraform-test.git",
              "cd /opt/terraform-test && ansible-playbook -vvi inventory run.yml",
             ]

    connection {
      type     = "ssh"
      host     = "${self.network_interface.0.addresses.0}"
      private_key = "${file("/root/.ssh/id_rsa")}"
#      user     = "root"
#      password = "junker"
#      agent = "false"
    }
  }

}

# IPs: use wait_for_lease true or after creation use terraform refresh and terraform show for the ips of domain

