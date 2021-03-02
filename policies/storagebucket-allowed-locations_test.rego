package storagebucketallowedlocations

test_storage_bucket_allowed_location {
	input := input_storage_bucket("US")
	results := violation with input as input
	count(results) == 0
}

test_storage_bucket_disallowed_location {
	input := input_storage_bucket("NOPE")
	results := violation with input as input
	count(results) == 1
}

test_storage_bucket_missing_location {
	input := input_storage_bucket_missing_location
	results := violation with input as input
	count(results) == 1
}

input_storage_bucket_missing_location = {
	"parameters": {"locations": [
		"ASIA",
		"EU",
		"US",
		"ASIA1",
		"EUR4",
		"NAM4",
	]},
	"review": {
		"object": {"spec": {"lifecycleRule": [{
			"action": {"type": "Delete"},
			"condition": {"age": 7},
		}]}},
	},
}

input_storage_bucket(location) = output {
	output = {
		"parameters": {"locations": [
			"ASIA",
			"EU",
			"US",
			"ASIA1",
			"EUR4",
			"NAM4",
		]},
		"review": {
			"object": {
				"apiVersion": "storage.cnrm.cloud.google.com/v1beta1",
				"kind": "StorageBucket",
				"metadata": {
					"annotations": {
						"cnrm.cloud.google.com/force-destroy": "false",
						"cnrm.cloud.google.com/management-conflict-prevention-policy": "resource",
						"cnrm.cloud.google.com/project-id": "hightowerlabs",
					},
					"creationTimestamp": "2021-03-08T02:35:10Z",
					"generation": 1,
					"name": "hightowerlabs-kcc-storage-bucket",
					"namespace": "default",
					"uid": "645084e4-8cf9-498e-bb45-66b65f666939",
				},
				"spec": {
					"lifecycleRule": [{
						"action": {"type": "Delete"},
						"condition": {"age": 7},
					}],
					"location": location,
				}
			}
		}
	}
}
