pipeline {
    agent any
    tools {
        jdk 'jdk17'
        nodejs 'node23'
    }
    environment {
        SCANNER_HOME=tool 'sonar-scanner'
    }
    stages {
        stage ("clean workspace") {
            steps {
                cleanWs()
            }
        }
        stage ("Git Checkout") {
            steps {
                git 'https://github.com/Saiekku7/DevOps-Project-Zomato.git/'
            }
        }
        stage("Sonarqube Analysis"){
            steps{
                withSonarQubeEnv('sonar-server') {
                    sh ''' $SCANNER_HOME/bin/sonar-scanner -Dsonar.projectName=zomato \
                    -Dsonar.projectKey=zomato '''
                }
            }
        }
        // stage("Code Quality Gate"){
        //    steps {
        //         script {
        //             waitForQualityGate abortPipeline: false, credentialsId: 'Sonar-token' 
        //         }
        //     } 
        // } 
        stage("Install NPM Dependencies") {
            steps {
                sh "npm install"
            }
        }
        stage('OWASP FS SCAN') {
            steps {
                dependencyCheck additionalArguments: '--scan ./ --disableYarnAudit --disableNodeAudit -n', odcInstallation: 'DP-Check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
    }
}
        stage ("Trivy File Scan") {
            steps {
                sh "trivy fs . > trivy.txt"
            }
        }
        stage ("Build Docker Image") {
            steps {
                sh "docker build -t zomato ."
            }
        }
        stage ("Tag & Push to DockerHub") {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker') {
                        sh "docker tag zomato saiekku7/zomato:latest "
                        sh "docker push saiekku7/zomato:latest "
                    }
                }
            }
        }
        stage('Docker Scout Image') {
            steps {
                script{
                   withDockerRegistry(credentialsId: 'docker', toolName: 'docker'){
                       sh 'docker-scout quickview saiekku7/zomato:latest'
                       sh 'docker-scout cves saiekku7/zomato:latest'
                       sh 'docker-scout recommendations saiekku7/zomato:latest'
                   }
                }
            }
        }
        stage ("Deploy to Container") {
            steps {
                sh 'docker run -d --name zomato -p 3000:3000 saiekku7/zomato:latest'
            }
        }
    }
    
    post {
    always {
        emailext attachLog: true,
            subject: "'${currentBuild.result}'",
            body: """
                <html>
                <body>
                    <div style="background-color: #FFA07A; padding: 10px; margin-bottom: 10px;">
                        <p style="color: white; font-weight: bold;">Project: ${env.JOB_NAME}</p>
                    </div>
                    <div style="background-color: #90EE90; padding: 10px; margin-bottom: 10px;">
                        <p style="color: white; font-weight: bold;">Build Number: ${env.BUILD_NUMBER}</p>
                    </div>
                    <div style="background-color: #87CEEB; padding: 10px; margin-bottom: 10px;">
                        <p style="color: white; font-weight: bold;">URL: ${env.BUILD_URL}</p>
                    </div>
                </body>
                </html>
            """,
            to: 'saisudeer88@gmail.com',
            mimeType: 'text/html',
            attachmentsPattern: 'trivy.txt'
        }
    }
    
}

# webhook 
github -> jenkins  http://ec2-16-170-152-5.eu-north-1.compute.amazonaws.com:8080/github-webhook/ in github; in jenkins poll scm and checkout from scm give repourl authentication and jenkinsfile location
sonarqube -> jenkins 
jenkins http://ec2-16-170-152-5.eu-north-1.compute.amazonaws.com:8080/sonarqube-webhook/

eksctl create cluster --name demo-eks --region eu-central-1 --node-type t3.medium --nodes-min 2 --nodes-max 2 --zones eu-central-1a,eu-central-1b
__________________________________________________________________________________________________________________________
__________________________________________________________________________________________________________________________


# i ran prometheus grafana sonara as docker images 
# 80 8080-jen 9000-sonar 9090-pr 9091-graf 
docker run -d --name prometheusX --restart unless-stopped -p 9090:9090 \
  -v /prometheus/config/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v /prometheus/data/:/prometheus prom/prometheus

chmod -R 777 /prometheus/data/
docker restart prometheusX

docker run -d --name grafana -p 9091:3000 grafana/grafana
mkdir -p /prometheus/{config,data}
sudo nano /prometheus/config/prometheus.yml

## 🔹 Step 2: Install Prometheus
 
```bash
# Download Prometheus
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz
 
# Extract
tar xvf prometheus-2.54.1.linux-amd64.tar.gz
mv prometheus-2.54.1.linux-amd64 prometheus

## prometheus.yml
sudo tee /opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
           - "ec2-16-170-152-5.eu-north-1.compute.amazonaws.com:9093"

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
   - "alert.rule.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: "prometheus"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node-exporter"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["ec2-16-170-152-5.eu-north-1.compute.amazonaws.com:9100"]

  - job_name: "jenkins"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.
    metrics_path: "/prometheus"
    static_configs:
      - targets: ["ec2-16-170-152-5.eu-north-1.compute.amazonaws.com:8080"]

  - job_name: "alert-manager"
    static_configs:   
      - targets: ["ec2-16-170-152-5.eu-north-1.compute.amazonaws.com:9093"] 
EOF
      

sudo nano /opt/prometheus/rules.yml # for docker /prometheus/config/alert.rule.yml
# alert.rule.yml
groups:
- name: node_alerts
  rules:
  - alert: HighCPUUsage
    expr: (100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)) > 80
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage on {{ $labels.instance }}"
      description: "CPU > 80% for 2 minutes."
 
  - alert: NodeDown
    expr: up{job="node-exporter"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Node down: {{ $labels.instance }}"
      description: "Node exporter target is unreachable."




# node-exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
tar xvf node_exporter-1.8.1.linux-amd64.tar.gz
cd node_exporter-1.8.1.linux-amd64
./node_exporter

# (or)

Node Exporter exposes Linux server metrics.
 
```bash
# Download latest Node Exporter
cd /opt
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
 
# Extract
tar xvf node_exporter-1.8.1.linux-amd64.tar.gz
mv node_exporter-1.8.1.linux-amd64 node_exporter
 
# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target
 
[Service]
User=nobody
ExecStart=/opt/node_exporter/node_exporter
 
[Install]
WantedBy=default.target
EOF
 
# Enable & start
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

## 🔹Install Alertmanager
 
```bash
cd /opt
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
tar xvf alertmanager-0.27.0.linux-amd64.tar.gz
mv alertmanager-0.27.0.linux-amd64 alertmanager
 
# Alertmanager.yml  smtp is not working so use slack only
sudo tee /opt/alertmanager/alertmanager.yml <<EOF
global:
  resolve_timeout: 5m
  # Gmail SMTP
  smtp_from: 'saisudeer88@gmail.com'
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'saisudeer88@gmail.com'
  smtp_auth_identity: 'saisudeer88@gmail.com'
  smtp_auth_password: 'hppjpiyt8qoglbtn'   # App password
  smtp_require_tls: true
 
route:
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  group_by: ['alertname']
 
  # Default route → send all alerts to Slack
  receiver: slack_notifications
 
  # Sub-route → send CRITICAL alerts to Email
  routes:
  - match:
      severity: critical
    receiver: email_notifications
 
receivers:
- name: slack_notifications
  slack_configs:
  - channel: '#dev'
    send_resolved: true
    api_url: 'https://hooks.slack.com/services/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'
    title: |-
      [{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}
    text: |-
      *Alert:* {{ .CommonLabels.alertname }}
      *Instance:* {{ .CommonLabels.instance }}
      *Severity:* {{ .CommonLabels.severity }}
      *Description:* {{ .CommonAnnotations.description }}
 
- name: email_notifications
  email_configs:
  - to: 'saisudeer88@gmail.com'
    send_resolved: true
 
inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['alertname', 'instance']
EOF
```
 
👉 Create systemd service:
 
```bash
sudo tee /etc/systemd/system/alertmanager.service <<EOF
[Unit]
Description=Alertmanager
After=network.target
 
[Service]
User=nobody
ExecStart=/opt/alertmanager/alertmanager \
  --config.file=/opt/alertmanager/alertmanager.yml \
  --storage.path=/opt/alertmanager/data
 
[Install]
WantedBy=default.target
EOF
 
sudo nano /etc/systemd/system/alertmanager.service 
sudo mkdir -p /opt/alertmanager/data \
sudo chown -R nobody:nogroup /opt/alertmanager/data/ \
sudo systemctl daemon-reload \
sudo systemctl restart alertmanager \
sudo systemctl status alertmanager 

sudo nano /etc/systemd/system/prometheus.service 
sudo mkdir -p /opt/prometheus/data 
sudo chown -R nobody:nogroup /opt/prometheus/data/ 
sudo systemctl daemon-reload 
sudo systemctl restart prometheus 
sudo systemctl status prometheus 
```

__________________________________________________________________________________________________________________________
__________________________________________________________________________________________________________________________

# P+G inside EKS 
https://chatgpt.com/c/68dca83d-5830-8322-ada3-bde6035ae679 
## 1. Install ArgoCD on EKS (NodePort)
 
```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
 
helm install argocd argo/argo-cd -n argocd \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30007 \
  --set server.service.nodePortHttps=30008
```
 
👉 Access ArgoCD at:
`http://<NodeIP>:30007` (HTTP)
`https://<NodeIP>:30008` (HTTPS)
 
---
# argo admin 1zLm8Xd0XKcnm4ra

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30009 \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30010 \
  --set alertmanager.service.type=NodePort \
  --set alertmanager.service.nodePort=30011

NAME: kube-prometheus-stack
LAST DEPLOYED: Wed Oct  1 04:43:51 2025
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=kube-prometheus-stack"

Get Grafana 'admin' user password by running:

  kubectl --namespace monitoring get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo  
  # prom-operator

Access Grafana local instance:

  export POD_NAME=$(kubectl --namespace monitoring get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack" -oname)
  kubectl --namespace monitoring port-forward $POD_NAME 3000

kubectl delete pod -n monitoring prometheus-kube-prometheus-stack-prometheus-0 

# for monitoring the pod we can use i.annotations ii.ServiceMonitor/PodMonitor
# cm.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
        listen 80;
        server_name localhost;
        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
        location /stub_status {
            stub_status;
        }
    }

# dep.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      - name: nginx-exporter
        image: nginx/nginx-prometheus-exporter:0.11.0
        args:
        - "-nginx.scrape-uri=http://127.0.0.1:80/stub_status"
        ports:
        - containerPort: 9113
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config

# srv.yml
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: metrics
    port: 9113
    targetPort: 9113
  selector:
    app: nginx-demo

# servicemonitor.yml --> match with helm release ie after helm install <kube-prometheus-stack>, app:nginx-demo for application 
kind: ServiceMonitor
metadata:
  name: nginx-demo-sm
  namespace: monitoring
  labels:
    release: kube-prometheus-stack 
spec:
  selector:
    matchLabels:
      app: nginx-demo
  namespaceSelector:
    matchNames:
      - default
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s


kubectl apply -f cm.yml -f dep.yml -f ser.yml -f mon.yml

# example test-rule.yml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alert-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: node-and-nginx-alerts
      rules:
        - alert: HighNodeCPUUsage
          expr: (1- rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100 > 90
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage on node {{ $labels.instance }}"
            description: "CPU usage is above 80% for more than 1 minutes."
 
        - alert: HighNginxRequests
          expr: rate(nginx_http_requests_total[1m]) > 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "High request rate on Nginx {{ $labels.instance }}"
            description: "Request rate is above 100 requests per second."
 
        - alert: NginxDown
          expr: up{job="nginx-demo"} > 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Nginx exporter down for {{ $labels.instance }}"
            description: "Prometheus target for Nginx exporter is down."

## Alerting for smtp
kubectl -n monitoring create secret generic gmail-smtp \
  --from-literal=smtp_password=hjppiytytaogltbn

# alertmanager.yml am.yml
global:
  resolve_timeout: 5m
  
route:
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  group_by: ['alertname']
 
  # Default route → send all alerts to Slack
  receiver: slack_notifications
 
  receivers:
- name: slack_notifications
  slack_configs:
  - channel: '#dev'
    send_resolved: true
    api_url: 'https://hooks.slack.com/services/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'
    title: |-
      [{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}
    text: |-
      *Alert:* {{ .CommonLabels.alertname }}
      *Instance:* {{ .CommonLabels.instance }}
      *Severity:* {{ .CommonLabels.severity }}
      *Description:* {{ .CommonAnnotations.description }}
  
inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['alertname', 'instance']


# apply config to alertmanager
kubectl -n monitoring create secret generic alertmanager-kube-prometheus-stack-alertmanager \
  --from-file=alertmanager.yaml=am.yml \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete pod -l app.kubernetes.io/name=alertmanager -n monitoring


# mani routemanger.yml
route:
  # fallback receiver
  receiver: admin
  group_by: [category]
  group_wait: 30s
  group_interval: 4m
  repeat_interval: 4h
  routes:
    # Star Solutions.
  - match:
      app_type: linux
    # fallback receiver
    receiver: ss-admin
    routes:
    # Linux team
    - match:
        app_type: windows
      # fallback receiver
      receiver: windows-team-admin
      routes:
      - match:
          severity: critical
        receiver: windows-team-manager
      - match:
          severity: warning
        receiver: windows-team-lead
 
    # Windows team
    - match:
        app_type: windows
      # fallback receiver
      receiver: windows-team-admin
      routes:
      - match:
          severity: critical
        receiver: windows-team-manager
      - match:
          severity: warning
        receiver: windows-team-lead
 
inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['app_type', 'category']
 
 
receivers:
- name: admin
  slack_configs:
  - channel: '#prometheus-alerts'
    api_url: 'https://hooks.slack.com/services/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'
 
- name: ss-admin
  email_configs:
  - to: 'johhnydepp55@gmail.com'
 
- name: linux-team-admin
  email_configs:
  - to: 'johhnydepp55@gmail.com'
 
- name: linux-team-lead
  email_configs:
  - to: 'johhnydepp55@gmail.com'
 
- name: linux-team-manager
  email_configs:
  - to: 'johhnydepp55@gmail.com'
 
- name: windows-team-admin
  email_configs:
  - to: 'johhnydepp55@gmail.com'
 
- name: windows-team-lead
  email_configs:
  - to: 'johhnydepp55@gmail.com'
 
- name: windows-team-manager
  email_configs:
  - to: 'johhnydepp55@gmail.com'
