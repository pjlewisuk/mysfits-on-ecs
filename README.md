# Deploy Mythical Mysfits on Amazon ECS

Deploying and running Mythical Misfits on Amazon ECS

## Preparation

* Install `jq`: `brew install jq`
* Switch CLI credentials to correct AWS account
* Deploy `mysfits-cfn.yaml` in [CloudFormation console](https://console.aws.amazon.com/cloudformation/home) with stack name `mysfits`
* Update `task-def-ec2.json` with latest `DDB_TABLE_NAME` and `UPSTREAM_URL` from `mysfits` CloudFormation stack
* Run `script/setup.sh` to populate the DynamoDB table and S3 bucket
* Set a couple of useful environment variables:
```bash
export AWS_ACCOUNT_ID=112233445566
export AWS_REGION=eu-west-1
```

## Run

1. Create Amazon ECR repository in [ECR Console](https://console.aws.amazon.com/ecr/repositories?region=eu-west-1#)
    * **Create repository**
    * **Repository name:** mysfits-monolith
    * **Scan on push:** Enabled
    * Show empty repository
2. Pull Olly's Docker image and push into Amazon ECR:
    * ```bash
      docker pull ollypom/mysfits:v3
      docker tag ollypom/mysfits:v3 ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mysfits-monolith:latest
      docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mysfits-monolith:latest
      ```
    * Return to mysfits-monolith repository in the [ECR Console](https://console.aws.amazon.com/ecr/repositories/mysfits-monolith/?region=eu-west-1) to show the image we've just pushed
3. Open [CloudFormation console](https://console.aws.amazon.com/cloudformation/home?#/stacks/) and view the Outputs tab of the `mysfits` stack.
    * Open the `LoadBalancerDNS` URL in a new tab
    * Open the `S3WebsiteURL` URL in a new tab
    * Switch to the load balancer tab and show that you receive a **503 Service Temporarily Unavailable** error message - this is because there are no instances or tasks registered into your load balancer to retrieve the relevant data from the DynamoDB table!
    * Switch to the S3 website tab, and show that although you have a pretty-looking webpage, there's no content on it - this is because the page calls out to the load balancer to populate it with data, and we've already seen that there's no response from the load balancer at this time
4. Create ECS cluster using the [ECS console](https://console.aws.amazon.com/ecs/home#/clusters)
    * Create Cluster
    * Run through cluster template options:
      * **Networking only** - customers only need to configure the networking, and Tasks are hosted using AWS Fargate, which takes care of the data plane infrastructure
      * **EC2 Linux + Networking** - customers configure the networking **and** one or more auto scaling groups of Linux instances
      * **EC2 Windows + Networking** - customers configure the networking **and** one or more auto scaling group of Windows instances
    * Select **EC2 Linux + Networking** and continue
    * Configure the cluster with the following settings:
      * **Cluster name:** mysfits-cluster
      * **Provisioning Model:** On-Demand Instance
      * **EC2 instance type:** m5.xlarge
      * **Number of instances:** 3
      * **Key pair:** \<select your key pair\>
      * **VPC:** mysfits-vpc
      * **Subnets:** mysfits-privateSubnet1, mysfits-privateSubnet2, mysfits-privateSubnet3
      * **Security group:** mysfits-ecsHostSecurityGroup
      * **Container instance IAM role:** mysfits-ecsInstanceRole
      * **CloudWatch Container Insights:** [x] Enable Container Insights
5. View [ECS Instances](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits/containerInstances) tab in the cluster details, and/or view [EC2 Instances](https://eu-west-1.console.aws.amazon.com/ec2/v2/home?region=eu-west-1#Instances:search) in the EC2 console
6. Deploy Container Insights into cluster using CloudFormation template in [docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-ECS-instancelevel.html):
      ```bash
      ClusterName=mysfits-cluster
      Region=eu-west-1
      aws cloudformation create-stack --stack-name CWAgentECS-${ClusterName}-${Region} \
        --template-body file://cwagent-ecs-instance-metric-cfn.json \
        --parameters ParameterKey=ClusterName,ParameterValue=${ClusterName} \
                    ParameterKey=CreateIAMRoles,ParameterValue=True \
        --capabilities CAPABILITY_NAMED_IAM \
        --region ${Region}
      ```
7. Open the [Services](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/services) tab to show the new `cwagent-daemon-service` service
    * Highlight **Desired tasks** and **Running tasks** (which should be the same)
    * Switch to the [Tasks](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/tasks) tab to show running tasks (should be one per container instance)
8. Create ECS Task Definition using the [ECS Console](https://console.aws.amazon.com/ecs/home#/taskDefinitions)
    * Select **EC2** launch type, as we've already provisioned some Container Instances for this
    * Scroll down through settings, talking through what some of them do, and entering some dummy values if you wish
    * Click on **Add Container** button and scroll through settings on this page too
    * Click **Cancel** to return to the Task Definition configuration page
    * Scroll down to **Configure via JSON** button and click it
    * Copy contents of `task-def-ec2.json` and paste into editor
    * Click **Save** to continue
9.  Review the Task definition revision that's been created, pointing out that this is a template for launching your containers later
10. Create an ECS Service in the [ECS Console](https://console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/services) using the Task Definition you just created 
    * **Launch type:** EC2
    * **Task definition:**
      * **Family:** mysfits-monolith
      * **Revision:** (latest)
    * **Cluster:** mysfits-cluster
    * **Service name:** monolith-service
    * **Service type:** REPLICA
    * **Number of tasks:** 1
    * **Minimum healthy percent:** 100
    * **Maximum percent:** 200
    * Click the **Next Step** button to continue to network configuration
    * **Cluster VPC:** mysfits-vpc
    * **Subnets:** mysfits-privateSubnet1, mysfits-privateSubnet2, mysfits-privateSubnet3
    * **Security groups:** Edit
      * **Select existing security group:** mysfits-ServiceSecurityGroup
      * Click **Save** to return to service network configuration
    * **Load balancer type:** Application Load Balancer
    * **Load balancer name:** mysfits-alb
    * **Container name : port:** monolith-service:8080:8080
    * Click **Add to load balancer** button
    * **Production listener port:** Select "80:HTTP" from down-down list
    * **Target group name:** Select "mysfi-Myth-..." from drop-down list
    * Click **Next step** button to continue to auto scaling configuration
    * **Service Auto Scaling:** Do not adjust the service's desired count
    * Click **Next step** button to continue to review
    * Click **Create Service** button to create the service
11. Review the Service that's been created
    * Switch to the [Tasks](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/services/monolith-service/tasks) tab and show that the new task is in the `PROVISIONING` state
    * Switch to the [Logs](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/services/monolith-service/logs) tab to show the Task starting up
      * Highlight the Task ID on the right-most column
      * Refresh the logs and see the reqests coming in from the ALB for the healthcheck
    * Switch to the [Events](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/services/monolith-service/events) tab to show what's happening in the background - run through the logs for provisioning tasks, registering into the load balancer target group, and then reaching steady state
    * Switch back to the [Tasks](https://eu-west-1.console.aws.amazon.com/ecs/home?region=eu-west-1#/clusters/mysfits-cluster/services/monolith-service/tasks) tab and show that the task is now in the `RUNNING` state
12. Review the running application
    * Switch to the load balancer tab you opened in Step 3), and refresh the page to show the health check response
    * Append `/mysfits` to the URL to show data being returned from the DynamoDB table
    * Switch the S3 website tab you opened in Step 3), and refresh the page to 
    * Click on **View Profile** for a couple of the mysfits to show more information about them
13. Switch to the [CloudWatch Container Insights Performance Monintoring console](https://console.aws.amazon.com/cloudwatch/home?#container-insights:performance)
    * Select **ECS Clusters** -> **mysfits-cluster** from the drop-downs at the top of the page
    * Quickly walk through what the graphs are showing
    * Switch to the **ECS Instances** -> **mysfits-cluster** from the drop-downs
    * Highlight how the graphs have changed and that we now see a breakdown of resource utilization by instance
    * Switch to the **ECS Services** -> **mysfits-cluster** from the drop-downs
    * Comment how the graphs are now showing aggregate utilization across all tasks in a particular service
    * Add a filter to show only **monolith-service**

## Cleaning Up

1. Delete the `CWAgentECS-mysfits-cluster` CloudFormation stack
2. Delete the `EC2ContainerService-mysfits-cluster` CloudFormation stack
3. Empty the `mysfits-mythicalbucket` S3 bucket
4. Delete the `mysfits` CloudFormation stack
5. Delete the `mysfits-cluster` ECS cluster
6. Deregister all revisions of the `mysfits-monolith` Task Definition
7. Delete the `mysfits-monolith` ECR repository
8. Delete any related CloudWatch Log Groups