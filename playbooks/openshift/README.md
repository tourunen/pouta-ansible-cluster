# OpenShift Origin playbooks

These playbooks can be used to assist deploying an OpenShift Origin cluster in cPouta. The bulk of installation
is done with the official [installer playbook](https://github.com/openshift/openshift-ansible).

*NOTE:* This document is not a complete guide, but mostly a checklist for persons already knowing
what to do or willing to learn. Do not expect that after completing the steps you have a usable OpenShift environment.

## Playbooks

### provision.yml

- takes care of creating the resources in cPouta project
    - VMs with optionally booting from volume
    - volumes for persistent storage
    - common and master security groups

- writes an inventory file to be used by later stages

### heat_provision.yml

- an alternative provisioning method to provision.yml that uses OpenStack Heat
  instead of using the other OpenStack APIs separately through Ansible
- currently more opinionated compared to provision.yml, but also a lot faster
  especially for multimaster deployments

### pre_install.yml

- adds basic tools
- installs and configures
    - docker
    - internal DNS
- configures persistent storage

### post_install.yml

- creates NFS volumes for OpenShift
- puts the registry on persistent storage
- customizes the default project template

### deprovision.yml

- used to tear the cluster resources down when using provision.yml

### heat_deprovision.yml

- used to tear the cluster resources down when using heat_provision.yml

### site.yml

- aggregates all installation steps after provisioning into a single playbook

### heat_site.yml

- aggregates all installation steps including provisioning using Heat into a
  single playbook

## Example installation process

This is a log of an example installation of a proof of concept cluster with

- one master
    - public IP
    - two persistent volumes, one for docker + swap, one for NFS persistent storage
- four nodes
    - one persistent volume for docker + swap

### Prerequisites

#### Alternative 1: native environment
Shell environment with
- OpenStack credentials for cPouta 
- python virtualenv with ansible==2.3, shade, dnspython and pyopenssl
- venv should have latest setuptools and pip (pip install --upgrade pip setuptools)
- metrics needs some extra packages on the bastion host
  - sudo yum install java-1.8.0-openjdk-headless python-passlib httpd-tools
- if you have SELinux enabled, either disable that or make sure the virtualenv has libselinux-python
- ssh access to the internal network of your project
    - either run this on your bastion host
    - or set up ssh forwarding through your bastion host in your ~/.ssh/config
    - please test ssh manually after provisioning 

There is a requirements.txt file that you can use to install the Python dependencies:

    $ mkvirtualenv --system-site-packages -r requirements.txt pac

The reason `--system-site-packages` is used here is because libselinux-python
is only available via RPM and must be taken from the system wide site-packages
location.

For packages on CentOS-7, see: [Creating a bastion host](../../CREATE_BASTION_HOST.md)

For automatic, self-provisioned app routes to work, you will need a wildcard DNS CNAME for your master's public IP.
 
In general, see https://docs.openshift.org/latest/install_config/install/prerequisites.html

#### Alternative 2: containerized environment for Heat based deployment

We also have a deployment container with all dependencies preinstalled. To build the container, 
check out PAC git repo (see below) and run the build script located in `container-src/pac-deployer`:
 
    cd ~/git/pouta-ansible-cluster/container-src/pac-deployer 
    sudo ./build.bash
    
To launch a shell in a temporary container for deployment, run

    cd ~/git/pouta-ansible-cluster/playbooks/openshift
    sudo ./run_deployment_container.bash

The script assumes that the environments directory is called openshift-environments and located
in a sibling directory next to PAC. If Docker containers can be launched without 'sudo',
that can be left out in the commands above.

__Note on SELinux__: If you are running under SELinux enforcing mode, the container processes
may not be able to access the volumes by default. To enable access from containerized 
processes, change the labels on the mounted directories:
 
    chcon -Rt svirt_sandbox_file_t \
        pouta-ansible-cluster openshift-ansible openshift-ansible-tourunen openshift-environments

### Clone playbooks

Clone the necessary playbooks from GitHub (here we assume they go under ~/git)
    
    $ mkdir -p ~/git && cd ~/git
    $ git clone https://github.com/CSCfi/pouta-ansible-cluster
    $ git clone https://github.com/openshift/openshift-ansible.git
    $ git clone https://github.com/tourunen/openshift-ansible.git openshift-ansible-tourunen
    $ cd openshift-ansible-tourunen
    $ git checkout release-1.5-csc

### Create a cluster config

Decide a name for your cluster, create a new directory and copy the example config file and modify that

    $ cd
    $ mkdir YOUR_CLUSTER_NAME
    $ cd YOUR_CLUSTER_NAME
    $ cp ~/git/pouta-ansible-cluster/playbooks/openshift/example_cluster_vars.yaml cluster_vars.yaml

Change at least the following config entries:

    cluster_name: "YOUR_CLUSTER_NAME" 
    ssh_key: "bastion-key"
    openshift_public_hostname: "your.master.hostname.here"
    openshift_public_ip: "your.master.ip.here"
    project_external_ips: ["your.master.ip.here"]

If you are deploying the cluster to a non-default network, remember to add and configure an interface to bastion host in
that network. The network also needs to be attached to a router.

### Run provisioning

Source your openstack credentials first

    $ source ~/openrc.bash

Provision the VMs and associated resources

    $ workon ansible-2.3
    $ ansible-playbook -v -e @cluster_vars.yaml ~/git/pouta-ansible-cluster/playbooks/openshift/provision.yml 

Before we run the configuration and installation playbook, we should define what persistent volumes are created.
Edit the NFS PV setup playbook to suit your needs.

    $ vi ~/git/openshift-ansible-tourunen/setup_lvm_nfs.yml

Note that registry will by default require one PV with size >= 128GiB .

Then run the configuration and installation playbook. This will take a while.

    $ ansible-playbook -v -e @cluster_vars.yaml -i openshift-inventory ~/git/pouta-ansible-cluster/playbooks/openshift/config.yml

### Advanced deployment mechanism using Heat (for automated build pipelines)

You will need to fulfill the prerequisites and clone the same repositories as
mentioned in the example installation instructions above. The recommended way 
is to use the containerized environment. In addition, you will
need to provide installation information via a separate repository/directory
instead of using cluster_vars.yml.

The format of this repository/directory is as follows:

```
environments
├── environment1
│   ├── groups
│   ├── group_vars
│   │   ├── all
│   │   │   ├── tls.yml
│   │   │   ├── vars.yml
│   │   │   ├── vault.yml
│   │   │   └── volumes.yml
│   │   ├── masters.yml
│   │   ├── nfsservers.yml
│   │   ├── node_lbs.yml
│   │   ├── node_masters.yml
│   │   ├── OSEv3
│   │   │   ├── vars.yml
│   │   │   └── vault.yml
│   │   └── ssd.yml
│   ├── hosts -> ../openstack.py
│   └── host_vars
├── openstack.py
└── environment2
    └...
```

Multiple environments are described here, all in their own subdirectory (here
environment1 and environment2, but the names can be whatever). You will need to
fill in the same data as would be filled in in cluster_vars.yml, except using
the standard Ansible group_vars and host_vars structure.

The roles of the files are:
  * groups: inventory file describing host grouping
  * group_vars: directory with config data specific to individual groups
  * host_vars: directory with config data specific to individual hosts
  * group_vars/all: config data relevant to all hosts in the installation
  * masters/nfsservers/node_lbs/node_masters etc.: config data for specific
    host groups in the OpenShift cluster
  * OSEv3: OpenShift installer config data
  * openstack.py: dynamic inventory script for OpenStack provided by the
    Ansible project
  * hosts: symlink to dynamic inventory script under environment specific
    directory
  * vault.yml files: encrypted variables for storing e.g. secret keys

For initialize_ramdisk.yml to work, you will need to populate the following variables:

  * ssh_private_key
  * tls_certificate
  * tls_secret_key
  * tls_ca_certificate
  * openshift_cloudprovider_openstack_auth_url
  * openshift_cloudprovider_openstack_auth_url
  * openshift_cloudprovider_openstack_username
  * openshift_cloudprovider_openstack_domain_name
  * openshift_cloudprovider_openstack_password
  * openshift_cloudprovider_openstack_tenant_id
  * openshift_cloudprovider_openstack_tenant_name
  * openshift_cloudprovider_openstack_region

Once you have all of this configured, running the actual installation is simple.

Change the current working directory to playbooks/openshift:

    $ cd ~/git/pouta-ansible-cluster/playbooks/openshift
    
Alternative when using containerized deployment:

    $ cd /opt/deployment/pouta-ansible-cluster/playbooks/openshift

Extract site specific data under /dev/shm/<cluster-name> by running 

    $ SKIP_DYNAMIC_INVENTORY=1 ansible-playbook initialize_ramdisk.yml \
    -i <path-to-environment-dir> \
    --ask-vault-pass

Source the extracted OpenStack credentials:

    $ source /dev/shm/<cluster-name>/openrc.sh

Then run heat_site.yml to provision infrastructure on OpenStack and install
OpenShift on this infrastructure:

    $ time ansible-playbook heat_site.yml \
    -i <path-to-environment-dir> \
    --ask-vault-pass

## Further actions

- open security groups
- start testing and learning
- get a proper certificate for master

## Deprovisioning

To deprovision all the resources, run

    $ ansible-playbook -v -e @cluster_vars.yaml \
    -e remove_nodes=1 -e remove_node_volumes=1 \
    -e remove_masters=1 -e remove_master_volumes=1 \
    -e remove_etcd=1 \
    -e remove_lbs=1 -e remove_lb_volumes=1 \
    -e remove_nfs=1 -e remove_nfs_volumes=1 \
    -e remove_security_groups=1 \
    ~/git/pouta-ansible-cluster/playbooks/openshift/deprovision.yml

### Deprovisioning when using Heat

    $ ansible-playbook heat_deprovision.yml \
    -i <inventory directory/file> \
    --ask-vault-pass

Partial deletes are not currently supported, as the Heat stack update process
does not nicely replace missing resources. This may be possible in newer
OpenStack versions.

## Security groups

- common
    - applied to all VMs
    - allow ssh from bastion
- infra
    - applied for all infrastructure VMs (masters, etcd, lb)
    - allow all traffic between infra VMs
- masters
    - applied to all masters
    - allow incoming DNS from common
- nodes
    - applied for all node VMs
    - allow all traffic from infra SG
- lb
    - applied to load balancers/router VMs
    - allow all traffic to router http, https and api port
- nfs
    - applied to NFS server
    - allow nfs v4 from all VMs
