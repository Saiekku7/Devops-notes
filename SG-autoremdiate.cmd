# SG Cleanup Lambda - Quick Guide

## Overview
This Lambda function scans all Security Groups (SGs) in all AWS regions or a specific region eu-north-1, removes rules not in the allowed CIDRs, and saves a report to S3. It also supports exempt SGs which will be skipped from cleanup.
Automatic remediation can be triggered via Cloudtrail and EventBridge rules.
---

## Prerequisites
- AWS Lambda execution role with appropriate permissions: 
- `ec2:DescribeSecurityGroups`
  - `ec2:RevokeSecurityGroupIngress`
  - `ec2:RevokeSecurityGroupEgress`
  - `cloudtrail:LookupEvents` (optional for who-modified info)
  - `s3:PutObject`
# ex-policy:
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ForEC2",
            "Effect": "Allow",
            "Action": [
                "ec2:RevokeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeRegions"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ForS3",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::sg-ruledel-bucket",
                "arn:aws:s3:::sg-ruledel-bucket/*"
            ]
        },
        {
            "Sid": "ForCloudtrail",
            "Effect": "Allow",
            "Action": [
                "cloudtrail:LookupEvents"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
- S3 bucket to store reports
- Python 3.9+ runtime
  


---

## Automatic Remediation Setup
1. CloudTrail: Ensure CloudTrail is enabled for all regions to track SG modifications.
2. EventBridge Rule: Create a rule to trigger Lambda on `AWS::EC2::SecurityGroup` changes.
   - Event pattern example:
   ```json
   {
     "source": ["aws.ec2"],
     "detail-type": ["AWS API Call via CloudTrail"],
     "detail": {
       "eventSource": ["ec2.amazonaws.com"],
       "eventName": ["AuthorizeSecurityGroupIngress", "AuthorizeSecurityGroupEgress"]
     }
   }
   ```
3. Target Setup: Configure the EventBridge rule to invoke this Lambda function whenever a SG rule change occurs.

---
## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ALLOWED_CIDRS` | Comma-separated list of allowed IP ranges. Leave blank to fill later. | `10.0.0.0/8,192.168.0.0/16` |
| `TEST_REGION` | AWS region to scan. Leave blank for all regions. | `` |
| `REPORT_BUCKET` | S3 bucket to store cleanup report | `sg-ruledel-bucket` |
| `EXEMPT_SG_IDS` | Comma-separated SG IDs to skip | `sg-0123abcd,sg-0456efgh` |

---

## Lambda Function Code

```python
import boto3
import os
import json
import ipaddress
from datetime import datetime
 
# Allowed CIDRs includes zscalerIps and VPC privateIPS
ALLOWED_CIDRS = os.environ.get("ALLOWED_CIDRS", """
8.25.203.0/24,64.74.126.64/26,70.39.159.0/24,72.52.96.0/26,87.58.64.0/18,89.167.131.0/24,101.2.192.0/18,
    104.129.192.0/20,112.196.99.180/32,136.226.0.0/16,137.83.128.0/18,147.161.128.0/17,159.254.0.0/16,159.254.62.0/23,
    159.254.66.0/23,165.225.0.0/17,165.225.192.0/18,167.103.0.0/16,167.106.0.0/16,170.85.0.0/16,175.107.128.0/18,
    185.46.212.0/22,194.9.96.0/20,194.9.112.0/22,194.9.116.0/24,198.14.64.0/18,199.168.148.0/22,205.220.0.0/17,
    209.55.128.0/18,209.55.192.0/19,213.152.228.0/24,216.52.207.64/26,216.218.133.192/26,10.0.0.0/8,172.16.0.0/12,
    192.168.0.0/16,100.64.0.0/10
""").replace("\n", "").split(",")
ALLOWED_NETWORKS = [ipaddress.ip_network(c.strip()) for c in ALLOWED_CIDRS if c.strip()]
 
# Test region: leave blank to scan all regions
TEST_REGION = os.environ.get("TEST_REGION", "eu-north-1").strip()
 
# S3 bucket to save reports
REPORT_BUCKET = os.environ.get("REPORT_BUCKET", "sg-ruledel-bucket")
 
# Exempt SGs (comma-separated)
EXEMPT_SG_IDS = os.environ.get("EXEMPT_SG_IDS", """
"sg-026a8bab5a6999ce6","sg-07463d1c1fac241e7","sg-0450f66de8ddce65e","sg-503e1d39","sg-099e0382f99ae6488","sg-05541dccd4642c3f5","sg-03cfdb76592c78ec4",
"sg-00d1f47112cc138c2","sg-0be838e57781307a8","sg-07ca66684687aa1d6","sg-005002eec1c6ef997","sg-014ae2060e22aa515","sg-052e32caf8f666768","sg-02320bf534eb224f5",
"sg-067621697d64847f0","sg-0f469d81912ac27c7","sg-08346b892cdb85116","sg-052084e38275092a7","sg-0057b0c99c403cf56","sg-0ef9348add434a4f8","sg-04461f633aac0edb4",
"sg-0d1e83c8b595d15b5","sg-09638b94a26a61e7e","sg-077a2e6bc74a9a4db","sg-0ec88ed2b4e61ce01","sg-002b5e6cd171a906b","sg-0b521c30701d61b7d","sg-0d3b5a1e4aa7048ac",
"sg-0db6451fb97e27644","sg-072f47654346dae76","sg-01bc6a8f0f3eb2c29","sg-0a5e69eb4d3d8a405","sg-0b6f86a42086ef9e5","sg-04b46bc98e3a983a4","sg-03550ef730a27761d",
"sg-01c2b4c46ea1d615a","sg-0bbbd7cc356d74512","sg-044165ee4dc1eb144","sg-073667eaf1f6961e1","sg-02f0cecd976250730","sg-006cf6bad64444bf3"
""").replace("\n", "").split(",")
EXEMPT_SG_IDS = [sg.strip() for sg in EXEMPT_SG_IDS if sg.strip()]
 
 
def get_modifier_from_cloudtrail(region, sg_id):
    """Query CloudTrail for who modified SG rules"""
    ct = boto3.client("cloudtrail", region_name=region)
    actors = []
    try:
        events = ct.lookup_events(
            LookupAttributes=[{"AttributeKey": "ResourceName", "AttributeValue": sg_id}],
            MaxResults=1
        ).get("Events", [])
 
        for e in events:
            user_identity = json.loads(e["CloudTrailEvent"]).get("userIdentity", {})
            user = user_identity.get("arn") or e.get("Username", "Unknown")
            event_time = e.get("EventTime")
            actors.append({
                "user": user,
                "time": event_time.strftime("%Y-%m-%dT%H:%M:%SZ") if event_time else "Unknown",
                "event": e.get("EventName")
            })
 
    except Exception as ex:
        actors.append({"user": "LookupError", "time": str(ex), "event": None})
 
    return actors
 
 
def clean_security_group(region_name, sg_id, report):
    # Skip exempted SGs
    if sg_id in EXEMPT_SG_IDS:
        print(f"⏭ Skipping exempted SG {sg_id} in {region_name}")
        return
 
    ec2 = boto3.client("ec2", region_name=region_name)
    print(f"\n🔍 Scanning SG {sg_id} in {region_name}")
 
    try:
        sg = ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]
 
        for direction in ["IpPermissions", "IpPermissionsEgress"]:
            ip_permissions = sg.get(direction, [])
 
            for permission in ip_permissions:
                ip_protocol = permission["IpProtocol"]
                from_port = permission.get("FromPort")
                to_port = permission.get("ToPort")
                ip_ranges = permission.get("IpRanges", [])
 
                to_remove = []
 
                for ip_range in ip_ranges:
                    cidr = ip_range.get("CidrIp")
                    if cidr:
                        try:
                            ip_net = ipaddress.ip_network(cidr)
                            if ALLOWED_NETWORKS and not any(ip_net.subnet_of(allowed_net) for allowed_net in ALLOWED_NETWORKS):
                                to_remove.append({"CidrIp": cidr})
                            elif not ALLOWED_NETWORKS:
                                to_remove.append({"CidrIp": cidr})
                        except ValueError:
                            to_remove.append({"CidrIp": cidr})
 
                if not to_remove:
                    continue

                # Build revoke entry
                ip_permission_entry = {"IpProtocol": ip_protocol, "IpRanges": to_remove}
                if ip_protocol in ["tcp", "udp"]:
                    ip_permission_entry["FromPort"] = from_port if from_port is not None else 0
                    ip_permission_entry["ToPort"] = to_port if to_port is not None else 65535
                elif ip_protocol in ["icmp", "icmpv6"]:
                    ip_permission_entry["FromPort"] = from_port if from_port is not None else -1
                    ip_permission_entry["ToPort"] = to_port if to_port is not None else -1
 
                revoke_params = {"GroupId": sg_id, "IpPermissions": [ip_permission_entry]}
 
                who_modified = get_modifier_from_cloudtrail(region_name, sg_id)

                # Append entry to report   
                report.append({
                    "region": region_name,
                    "sg_id": sg_id,
                    "direction": "Ingress" if direction == "IpPermissions" else "Egress",
                    "Protocol": ip_protocol,
                    "FromPort": ip_permission_entry["FromPort"],
                    "ToPort": ip_permission_entry["ToPort"],
                    "removed_rules": to_remove,
                    "who_modified": who_modified
                })

                # Revoke rules
                try:
                    if direction == "IpPermissions":
                        print(f"   🚫 Revoking Ingress in {sg_id}: {to_remove}")
                        ec2.revoke_security_group_ingress(**revoke_params)
                    else:
                        print(f"   🚫 Revoking Egress in {sg_id}: {to_remove}")
                        ec2.revoke_security_group_egress(**revoke_params)
                except Exception as e:
                    print(f"⚠ Error while revoking in {sg_id}: {str(e)}")
 
    except Exception as e:
        print(f"▲ Error in SG {sg_id}: {str(e)}")
 
 
def lambda_handler(event, context):
    report = []
 
    if TEST_REGION:
        regions = [TEST_REGION]
        print(f"🔹 Scanning only specified region: {TEST_REGION}")
    else:
        ec2_global = boto3.client("ec2")
        regions = [r["RegionName"] for r in ec2_global.describe_regions()["Regions"]]
        print("🔹 Scanning all regions")
 
    for region in regions:
        ec2 = boto3.client("ec2", region_name=region)
        sgs = ec2.describe_security_groups()["SecurityGroups"]
        for sg in sgs:
            clean_security_group(region, sg["GroupId"], report)
 
    # Save report only if any rules were removed
    if report:
        timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
        s3_key = f"sg-cleanup-reports/sg_report_{timestamp}.json"
        s3 = boto3.client("s3")
        s3.put_object(
            Bucket=REPORT_BUCKET,
            Key=s3_key,
            Body=json.dumps(report, indent=2),
            ContentType="application/json"
        )
        print(f"✅ Report saved to s3://{REPORT_BUCKET}/{s3_key}")
        return {"status": "remediation_complete", "report_s3_key": s3_key}
    else:
        print("✅ No rules to remove. No report created.")
        return {"status": "no_remediation_needed"}
```

---

## Usage
1. Deploy Lambda with this code.  
2. Set the **environment variables**.  
3. Trigger the Lambda.  
4. Check **S3** for the report (only if rules were removed).  
5. Exempt SGs are skipped automatically.

