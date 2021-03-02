package storagebucketallowedlocations

# Check if the location was set on the storage bucket resource.
#
# A storage bucket location must be set.
violation[{"msg": msg, "details": {"location": ""}}] {
	not input.review.object.spec.location
	msg := "missing location"
}

# Check if the storage bucket location is on the allowed list.
#
# Storage buckets can only be created in allowed locations as
# defined by the locations parameter.
violation[{"msg": msg, "details": {"location": location}}] {
	location := input.review.object.spec.location
	allowed_locations := input.parameters.locations

	# We can't use a simple set look up here:
    #
	#     not allowed_locations[location]
	#
	# because allowed_locations points to input.parameters.locations
	# which is a list and not a set. We could build a set based on
    # input.parameters.locations using a set comprehension:
    #
    #     allowed_locations := {a | a := input.parameters.locations[_]}
    #
	not contains(allowed_locations, location)

	msg := sprintf("%v location not allowed", [location])
}

# Check if variable s is a set containing variable e
# 
# Returns true if s contains e.
contains(s, e) {
  s[_] = e
}
