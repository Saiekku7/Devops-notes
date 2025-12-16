# ansible collections for infra provising with roles
cat demo/defaults/main.yml 
REGION: us-east-1
VPC_ID: vpc-094134f054127f353
SUBNET_ID: subnet-0adbcb3be5a0e9a90
SG_NAME: sg-ec2
SG_DESCRIPTION: SG for EC2 instances using Ansible
INSTANCE_NAME_1: EC2_Instance_1
INSTANCE_NAME_2: EC2_Instance_2
INSTANCE_NAME_3: EC2_Instance_3
INSTANCE_TYPE: t2.micro
KEYNAME: ansible
UBUNTU_AMI: ami-0ecb62995f68bb549

ubuntu@ip-172-31-69-187:~$ cat demo/vars/main.yml 
REGION: us-east-1
VPC_ID: vpc-094134f054127f353
SUBNET_ID: subnet-0adbcb3be5a0e9a90
SG_NAME: sg-ec2
SG_DESCRIPTION: SG for EC2 instances using Ansible
INSTANCE_NAME_1: EC2_Instance_1
INSTANCE_NAME_2: EC2_Instance_2
INSTANCE_NAME_3: EC2_Instance_3
INSTANCE_TYPE: t2.micro
KEYNAME: ansible
UBUNTU_AMI: ami-068c0051b15cdb816
RHEL_AMI: ami-0abcdef1234567890
s3_bucket_name: sai-bucket-1244

ubuntu@ip-172-31-69-187:~$ cat demo/tasks/main.yml 

- name: Create EC2 SG
  amazon.aws.ec2_security_group:
    name: ec2-group
    description: SG for EC2 instances using Ansible
    vpc_id: "{{ VPC_ID }}"
    region: "{{ REGION }}"
    aws_aess_y_id: "{{}}"
    aws_seet_id: "{{}}"
    rules:
      - proto: tcp
        from_port: 22
        to_port: 22
        cidr_ip: 0.0.0.0/0

      - proto: tcp
        from_port: 80
        to_port: 9000
        cidr_ip: 0.0.0.0/0

    rules_egress:
      - proto: -1
        from_port: 0
        to_port: 0
        cidr_ip: 0.0.0.0/0
  register: ec2_sg

- name: Output SG ID
  debug:
    msg: "Security Group ID is {{ ec2_sg.group_id }}"

- name: Create S3 bucket (minimal)
  amazon.aws.s3_bucket:
    name: "{{ s3_bucket_name }}"
    state: present
    aws_acced: "{{}}"
    aws_secr_id: "{{}}"

ubuntu@ip-172-31-69-187:~$ cat main.yaml 
---
- name: Creating SG and EC2 Instances
  hosts: master
  connection: local
  gather_facts: false
  become: true
  vars:
    REGION: us-east-1
  roles:
    - demo
