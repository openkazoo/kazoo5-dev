# Resources

When Kazoo gets an offnet request it loads the available resources and creates a list of all the resources that can handle the request based on the available Classifiers for each resource, then, Kazoo sorts the list of resources like this:

- If `resource.classifiers.{CLASSIFIER\_NAME}.weight\_cost` field is defined it will sort using that field’s value.
- If not, it will use the resource’s weight\_cost (resource.weight\_cost) value.

Once the list is sorted Kazoo will try to use the resources in the resulting order.

*NOTE:* classifiers and resources have a default weight\_cost value of 50 when not defined, it means if a resource is created and weight\_cost is not included on the request payload for the resource itself and/or for the classifiers it will be added by default by the API. Thus, the only way `resource.classifiers.{CLASSIFIER\_NAME}.weight_cost` can be undefined is when the classifier doesn’t exist at all. In which case, the resource.weight\_cost value will be used. This information can be seen/verified on the resources' [schema](https://github.com/2600hz/kazoo-crossbar/blob/master/priv/couchdb/schemas/resources.json).

With this in mind, if the desire is to prioritize per classifier, classifiers need to have different weight\_cost among resources. If classifiers have the same weight\_cost, resources will be used in any order. If the desire is to prioritize per resource, classifiers should have the same weight\_cost as the resource itself. This is because classifiers cannot have an undefined weight\_cost value.

## Resource Configuration Example

Omitting most of the resources' data (field/value pairs):

```json
{"name": "Carrier1",
 "weight_cost": 50,
 "classifiers":{
   "did_us": {
     "enabled": true,
     "prefix": "",
     "suffix": "",
     "emergency": false,
     "weight_cost": 50
    }
  }
}
```

```json
{"name": "Carrier2",
 "weight_cost": 50,
 "classifiers":{
   "did_us": {
     "enabled": true,
     "prefix": "",
     "suffix": "",
     "emergency": false,
     "weight_cost": 50
    }
  }
}
```

This is how a couple of resources look like right after they were created and not priority was set (weight\_cost was not included on request payload), as seen, it has the same weight\_cost for both, the resource itself and the classifiers (1 in this case: did\_us) within the resource.

If a device registered on Kazoo places a call to a US DID, Kazoo will get the list of resources that can handle this request, in this scenario both Carrier1 and Carrier2 can handle the request. Next, Kazoo tries to prioritize the resources, since both matching classifiers have the same weight\_cost, it will use resources in any order which means the resulting resources list can be any of:

- [Carrier1, Carrier2]
- [Carrier2, Carrier1]

Let's say Carrier2 is cheaper for US DIDs so the desire is to use/try it first for US DID requests, then we set `Carrier2.classifiers.did_us.weight_cost=1` and place another call, in this scenario Kazoo resulting resources list will be: [Carrier2, Carrier1].

Now, let's say I don’t care which carrier is cheaper, I just want all the request to go through Carrier1 if possible, Carrier2 otherwise, then we set Carrier1 to `{weight_cost: 1, classifiers.*.weight_cost: 1}` and Carrier2 to be like `{weight_cost: 2, classifiers.*.weight_cost: 2}` (note the * character, it means change weight_cost for every classifier). With these changes we ensure Carrier1 will be used for all the offnet requests, thus, the resulting resources list for every offnet request will be:

[Carrier1, Carrier2]
