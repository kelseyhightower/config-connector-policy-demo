# Config Connector Gatekeeper Tutorial

This tutorial walks you through creating and enforcing policies for [Config Connector](https://cloud.google.com/config-connector/docs/overview) Kubernetes resources using [Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/).

At a high level this tutorial will help you:

* Provision a GKE cluster to host the Config Connector and Gatekeeper control planes
* Create Gatekeeper policies to limit which locations Google Storage Buckets can be created in

## Setup

The set up process involves the following:

* Create a GKE cluster
* Install and configure Kubernetes Config Connector
* Install and configure Gatekeeper

Run the setup script to complete the above tasks:

```
./bin/setup
```

At this point you should have a GKE Cluster named `cad`:

```
gcloud container clusters list
```
```
NAME  LOCATION    MASTER_VERSION    MASTER_IP      MACHINE_TYPE  NODE_VERSION      NUM_NODES  STATUS
cad   us-west1-a  1.18.12-gke.1210  XX.XXX.XX.XX   e2-medium     1.18.12-gke.1210  3          RUNNING
```

The Config Connector control plane should also be up and running:

```
kubectl get pods -n cnrm-system
```
```
NAME                                            READY   STATUS    RESTARTS
cnrm-controller-manager-0                       2/2     Running   0       
cnrm-deletiondefender-0                         1/1     Running   0          
cnrm-resource-stats-recorder-7cf8996bbf-bt8pv   2/2     Running   0          
cnrm-webhook-manager-597f88457b-45n2c           1/1     Running   0          
cnrm-webhook-manager-597f88457b-gr9d6           1/1     Running   0         
```

## Install Gatekeeper

```
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.3/deploy/gatekeeper.yaml
```

Gatekeeper should be up and running in the `gatekeeper-system` namespace:

```
kubectl get pods -n gatekeeper-system
```
```
NAME                                             READY   STATUS    RESTARTS
gatekeeper-audit-84964f86f-f6vvk                 1/1     Running   0
gatekeeper-controller-manager-5bb5f9b4dd-jmlrm   1/1     Running   0
gatekeeper-controller-manager-5bb5f9b4dd-rgp9j   1/1     Running   0
gatekeeper-controller-manager-5bb5f9b4dd-xpfgr   1/1     Running   0
```

## Creating a Gatekeeper Policy

In this section we will create Gatekeeper policies to limit which GCS [bucket locations](https://cloud.google.com/storage/docs/locations) can be used when creating Storage Bucket resources.

Gatekeeper leverages [constraint templates](https://open-policy-agent.github.io/gatekeeper/website/docs/howto#constraint-templates) to define policies and [constraints](https://open-policy-agent.github.io/gatekeeper/website/docs/howto#constraints) to configure them. While we could jump directly into reviewing and deploying constraint templates and constraints it's important to understand the fundamental workflow for creating policies from scratch.

When writing policies it helps to understand the input that policies will use during the validation process. The input for this tutorial will be StorageBucket resource. The following Kubernetes manifest can be use to create a StorageBucket resource named `example-storage-bucket` in the `US` bucket location:

```
apiVersion: storage.cnrm.cloud.google.com/v1beta1
kind: StorageBucket
metadata:
  annotations:
    cnrm.cloud.google.com/force-destroy: "false"
  name: example-storage-bucket
spec:
  location: US
```

It's important to understand that Gatekeeper doesn't operate on Kubernetes resource object directly. Gatekeeper receives Kubernetes admission objects and turns them into  the input with a set of parameter define in constraints. This following is an example input object that is made available to your policies:

```
{
  "parameters": {
    "locations": [
      "ASIA",
      "EU",
      "US",
      "ASIA1",
      "EUR4",
      "NAM4"
    ]
  },
  "review": {
    ...
    "object": {
      "apiVersion": "storage.cnrm.cloud.google.com/v1beta1",
      "kind": "StorageBucket",
      "metadata": {
        "name": "example-storage-bucket",
        "namespace": "default",
      },
      "spec": {
        "lifecycleRule": [
          {
            "action": {
              "type": "Delete"
            },
            "condition": {
              "age": 7
            }
          }
        ],
        "location": "US"
      }
    }
  }
}
```

> Notice the `StorageBucket` resource is embedded under the `review` key.

Under the `policies` directory you'll find a policy written in Rego that ensures the `spec.location` field is set on StorageBucket objects and matches an approved GCS location.

```
ls -1 policies/
```
```
storagebucket-allowed-locations.rego
storagebucket-allowed-locations_test.rego
```

I find it much easier to craft standalone rego policies and test locally using native opa tooling before creating constraint templates used by Gatekeeper. Review the policies and run the following command to test them.

```
opa test policies/ -v
```
```
data.storagebucketallowedlocations.test_storage_bucket_allowed_location: PASS (636.042µs)
data.storagebucketallowedlocations.test_storage_bucket_disallowed_location: PASS (240.959µs)
data.storagebucketallowedlocations.test_storage_bucket_missing_location: PASS (81.125µs)
--------------------------------------------------------------------------------
PASS: 3/3
```

### Creating Constraint Templates

With a working set of rego policies we are ready to embed them in a constraint template. Constraint templates allow us to define gatekeeper policies and [custom resource definitions](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) that will allow us to configure the policies. In this case we will define a `StorageBucketAllowedLocations` resource that will allow us to define which GCS locations will be allowed. For example:

```
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: StorageBucketAllowedLocations
metadata:
  name: allowmultiregions
spec:
  match:
    kinds:
      - apiGroups: ["storage.cnrm.cloud.google.com"]
        kinds: ["StorageBucket"]
  parameters:
    locations:
      - "ASIA"
      - "EU"
      - "US"
```

The above `StorageBucketAllowedLocation` resource will reject `StorageBucket` objects with the `spec.location` field set to any value other than on of the GCS multi-region locations: ASIA, EU, US.  

Next, create a Gatekeeper [constraint template](https://open-policy-agent.github.io/gatekeeper/website/docs/howto#constraint-templates) named `storage-bucket-allowed-locations`:

```
kubectl apply -f templates/storage-bucket-allowed-locations.yaml
```

Create a Gatekeeper [constraint](https://open-policy-agent.github.io/gatekeeper/website/docs/howto#constraints) named `allow-multi-regions`:

```
kubectl apply -f constraints/allow-multi-regions.yaml
```

At this point the gatekeeper polices are in place

## Create GCS Buckets

With our Gatekeeper policies in place we now have the ability to restrict `StorageBucket` resources to a specific set of GCS bucket locations, specifically multi-region locations.

List the current set of `StorageBucket` resources managed by Config Connector:

```
kubectl get storagebuckets
```
```                      
No resources found in default namespace.
```

Create a unique `StorageBucket` bucket by appending the current GCP project name:

```
PROJECT_ID=$(gcloud config get-value project)
```

```
BUCKET_NAME="${PROJECT_ID}-kcc-storage-bucket"
```

```
cat << EOF > storage-bucket.yaml
apiVersion: storage.cnrm.cloud.google.com/v1beta1
kind: StorageBucket
metadata:
  annotations:
    cnrm.cloud.google.com/force-destroy: "false"
  name: ${BUCKET_NAME}
spec:
  uniformBucketLevelAccess: true
  lifecycleRule:
    - action:
       type: Delete
      condition:
       age: 7
EOF
```

Submit the `StorageBucket` manifest:

```
kubectl apply -f storage-bucket.yaml
```

You should get the following error message because we did not a the `spec.location` field:

```
Error from server ([denied by allowmultiregions] missing location): error when creating "storage-bucket.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [denied by allowmultiregions] missing location
```

This time set the `spec.location` field to an GCS bucket location not allowed:

```
cat << EOF > storage-bucket.yaml
apiVersion: storage.cnrm.cloud.google.com/v1beta1
kind: StorageBucket
metadata:
  annotations:
    cnrm.cloud.google.com/force-destroy: "false"
  name: ${BUCKET_NAME}
spec:
  location: "US-WEST1"
  uniformBucketLevelAccess: true
  lifecycleRule:
    - action:
       type: Delete
      condition:
       age: 7
EOF
```

Submit the `StorageBucket` manifest:

```
kubectl apply -f storage-bucket.yaml
```

You should get the following error because the `spec.location` was set to the `US-WEST1` bucket location which is not permitted by the policy.

```
Error from server ([denied by allowmultiregions] US-WEST1 location not allowed): error when creating "storage-bucket.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [denied by allowmultiregions] US-WEST1 location not allowed
```

This time set the `spec.location` field to one of the allowed GCS bucket locations:

> The `allowmultiregions` allows only multi-region bucket locations including ASIA, EU, and US. Review the `constraints/allow-multi-regions.yaml` for more details:

```
cat << EOF > storage-bucket.yaml
apiVersion: storage.cnrm.cloud.google.com/v1beta1
kind: StorageBucket
metadata:
  annotations:
    cnrm.cloud.google.com/force-destroy: "false"
  name: ${BUCKET_NAME}
spec:
  location: US
  uniformBucketLevelAccess: true
  lifecycleRule:
    - action:
       type: Delete
      condition:
       age: 7
EOF
```

Submit the `StorageBucket` manifest:

```
kubectl apply -f storage-bucket.yaml
```

```
storagebucket.storage.cnrm.cloud.google.com/hightowerlabs-kcc-storage-bucket created
```

No errors this time!

## Verification

```
kubectl get storagebuckets
```
```
NAME                               AGE
hightowerlabs-kcc-storage-bucket   53s
```

```
kubectl describe storagebuckets ${BUCKET_NAME}
```

```
Name:         hightowerlabs-kcc-storage-bucket
Namespace:    default
Labels:       <none>
Annotations:  cnrm.cloud.google.com/force-destroy: false
              cnrm.cloud.google.com/management-conflict-prevention-policy: resource
              cnrm.cloud.google.com/project-id: hightowerlabs
API Version:  storage.cnrm.cloud.google.com/v1beta1
Kind:         StorageBucket
Metadata:
  Creation Timestamp:  2021-03-11T18:51:14Z
  Resource Version:  17309973
  Self Link:         /apis/storage.cnrm.cloud.google.com/v1beta1/namespaces/default/storagebuckets/hightowerlabs-kcc-storage-bucket
  UID:               5e422837-676c-4871-8ec5-ec46b1c18438
Spec:
  Lifecycle Rule:
    Action:
      Type:  Delete
    Condition:
      Age:         7
      With State:  ANY
  Location:        US
  Storage Class:   STANDARD
Status:
  Conditions:
    Last Transition Time:  2021-03-11T18:51:15Z
    Message:               The resource is up to date
    Reason:                UpToDate
    Status:                True
    Type:                  Ready
  Self Link:               https://www.googleapis.com/storage/v1/b/hightowerlabs-kcc-storage-bucket
  URL:                     gs://hightowerlabs-kcc-storage-bucket
Events:
  Type    Reason    Age    From                      Message
  ----    ------    ----   ----                      -------
  Normal  Updating  2m10s  storagebucket-controller  Update in progress
  Normal  UpToDate  2m9s   storagebucket-controller  The resource is up to date
```

```
gsutil du -ch gs://hightowerlabs-kcc-storage-bucket
```

```
0 B          total
```
