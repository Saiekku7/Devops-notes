
# ansible roles for nginx setup
ansible-galaxy role init nginx  
tree nginx/
nginx/
├── README.md
├── defaults
│   └── main.yml
├── files
│   └── index.html
├── handlers
│   └── main.yml
├── meta
│   └── main.yml
├── tasks
│   └── main.yml
├── templates
│   └── nginx.conf.j2
├── tests
│   ├── inventory
│   └── test.yml
└── vars
    └── main.yml

nano nginx/defaults/main.yml
---
# defaults file for nginx

# Safe defaults  can be overridden from playbook, inventory, or extra_vars
webserver_package: nginx
webserver_service: nginx
webserver_port: 80
webserver_root: /var/www/html
webserver_conf_path: /etc/nginx/conf.d/app.conf

nano nginx/vars/main.yml # override 
webserver_user: ubuntu

nano nginx/tasks/main.yml # main tasks
---
- name: Install package
  ansible.builtin.package:
    name: "{{ webserver_package }}"
    state: present

- name: Create web root
  ansible.builtin.file:
    path: "{{ webserver_root }}"
    state: directory
    owner: "{{ webserver_user | default('root') }}"
    group: "{{ webserver_user | default('root') }}"
    mode: '0755'

- name: Deploy nginx config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: "{{ webserver_conf_path }}"
  notify: Restart webserver

- name: Deploy index.html
  ansible.builtin.copy:
    src: index.html
    dest: "{{ webserver_root }}/index.html"
    mode: '0644'

- name: Ensure service is running and enabled
  ansible.builtin.service:
    name: "{{ webserver_service }}"
    state: started
    enabled: true


nano nginx/handlers/main.yml # handlers
---
- name: Restart webserver
  ansible.builtin.service:
    name: "{{ webserver_service }}"
    state: restarted

nano nginx/files/index.html # files for role to use
<p><h> HEllo Guys.........................</h>im working </p>

nano nginx/templates/nginx.conf.j2

server {
    listen {{ webserver_port }};
    server_name _;
    root {{ webserver_root }};

    location / {
        try_files $uri $uri/ =404;
    }
}

nano server.yml # main playbook
---
- name: Configure web servers
  hosts: master
  become: true
  gather_facts: false
  roles:
    - role: nginx
      vars:
        webserver_port: 8080                # override default
        webserver_root: /opt/app/public     # override default

ansible-playbook server.yml
