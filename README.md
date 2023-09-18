# MongoDB Compound Wildcard Index Demo


## What

Wildcard indexes have improved in several ways in MongoDB 7.0. 

Notabley, wildcard indexes can now be compound, including additional non-wildcard fields.

Previously, wildcard indexes only acted as a single-field index on each indivudual target field, stored in a single index which included those fields.

Newly supported is the ability to include both wildcard fields and named individual fields in the same index.

This capability supports common use cases such as the `attribute-pattern` document design. In such cases, a sub-document contains a set of keys, but the presence of the keys varies from document to document.


Consider the case of the followin documents describing a prospect record in a CRM system

```javascript
{ _id: 35, name: 'Francis', status: 'customer', contact: {} }

{ _id: 36, name: 'Connor',  status: 'customer', contact: { cell: '07787 304928', fax: '0191 558 5860' }}

{ _id: 1,  name: 'Ethan',   status: 'customer', contact: { cell: '07943 819337' }}
```

1. Francis has no contact fields at all - just a name.
2. Connor has both a `cell` and a `fax `.
3. Ethan has only a `cell` phone number.

A wildcard index on `contact.**` would allow single-field match against one of the contact fields.

But query filtering on the `status` field *and* one of the wildcard fields would not be supported without a compound wildcard index.


## Demo

The playground demo file [`demo.mongodb`](demo.mongodb "demo.mongodb file") shows how to create a compound wildcard index.

Creating a Compound Wildcard Index

Create an index by supplying both a wildcard expression and an additional plain (non-wildcard) field(s).

```javascript
db.prospect.createIndex({ "contact.$**": 1, status:1 }, {name: "idx_compound_wild"})
```

### Query

This query leverages the compound index:

```javascript
db.prospect.find({'contact.cell':'07408 926850', status:'customer'})
```

Running `.explain(true)` on this query shows a winning plan that states our index named *idx_compound_wild* was used. The indexBounds entry shows that both the `contact.cell` and `status` fields were considered when processing the query agains the index.

```javascript
"winningPlan": {
      "queryPlan": {
        "stage": "FETCH",
        "planNodeId": 2,
        "inputStage": {
          "stage": "IXSCAN",
          "planNodeId": 1,
          "keyPattern": {
            "$_path": 1,
            "contact.cell": 1,
            "status": 1
          },
          "indexName": "idx_compound_wild",
          "isMultiKey": false,
          "multiKeyPaths": {
            "$_path": [],
            "contact.cell": [],
            "status": []
          },
          "isUnique": false,
          "isSparse": true,
          "isPartial": false,
          "indexVersion": 2,
          "direction": "forward",
          "indexBounds": {
            "$_path": [
              "[\"contact.cell\", \"contact.cell\"]"
            ],
            "contact.cell": [
              "[\"07408 926850\", \"07408 926850\"]"
            ],
            "status": [
              "[\"customer\", \"customer\"]"
            ]
          }
        }
```

### Intersection?

Index intersection is a strategy where more than one indexed fields are stated in a filter, and the result is computed by perforing a set intersection on the keys of 2 indexes.

While the strategy implementation is clearly implied when two simple indexes are at play on two separate fields, questions remain surrounding wildcard index. Will the mongo query planner choose to "intersect" the same wildcard index with itself somehow? Do we expect it will be smart about choosing to scan for two values, one found in a certain path `contact.cell`, then the second found in a different path `contact.fax` - both of which are contained with the same index?


Consider the following query:

```javascript
db.prospect.find({ 'contact.email': 'madtiwvab@what.not', 'contact.fax': '0121 062 9173'})
```

The query filters on two separate fields (`email` and `fax`) which are included in the wildcard index.

The query planner shows the following output:

```javascript
"winningPlan": {
      "queryPlan": {
        "stage": "FETCH",
        "planNodeId": 2,
        "filter": {
          "contact.email": {
            "$eq": "madtiwvab@what.not"
          }
        },
        "inputStage": {
          "stage": "IXSCAN",
          "planNodeId": 1,
          "keyPattern": {
            "$_path": 1,
            "contact.fax": 1,
            "status": 1
          },
          "indexName": "idx_compound_wild",
          "isMultiKey": false,
          "multiKeyPaths": {
            "$_path": [],
            "contact.fax": [],
            "status": []
          },
          "isUnique": false,
          "isSparse": true,
          "isPartial": false,
          "indexVersion": 2,
          "direction": "forward",
          "indexBounds": {
            "$_path": [
              "[\"contact.fax\", \"contact.fax\"]"
            ],
            "contact.fax": [
              "[\"0121 062 9173\", \"0121 062 9173\"]"
            ],
            "status": [
              "[MinKey, MaxKey]"
            ]
          }
        }
      },
      "slotBasedPlan": {
        "slots": "$$RESULT=s11 env: { s2 = Nothing (SEARCH_META), s5 = KS(3C636F6E746163742E666178003C30313231203036322039313733000A0104), s10 = {\"$_path\" : 1, \"contact.fax\" : 1, \"status\" : 1}, s3 = 1695076778554 (NOW), s6 = KS(3C636F6E746163742E666178003C3031323120303632203931373300F0FE04), s1 = TimeZoneDatabase(America/Grenada...Pacific/Efate) (timeZoneDB), s14 = \"madtiwvab@what.not\" }",
        "stages": "[2] filter {traverseF(s13, lambda(l1.0) { traverseF(getField(l1.0, \"email\"), lambda(l2.0) { ((l2.0 == s14) ?: false) }, false) }, false)} \n[2] nlj inner [] [s4, s7, s8, s9, s10] \n    left \n        [1] cfilter {(exists(s5) && exists(s6))} \n        [1] ixseek s5 s6 s9 s4 s7 s8 [] @\"6b0fb303-555b-449b-9877-faf4ac65459d\" @\"idx_compound_wild\" true \n    right \n        [2] limit 1 \n        [2] seek s4 s11 s12 s7 s8 s9 s10 [s13 = contact] @\"6b0fb303-555b-449b-9877-faf4ac65459d\" true false \n"
      }
    }
```

The above is a bit awkward. The `filter` term mentions the `contact.email `field alone. The `indexBounds` field mentions the `contact.fax` field only. Though one might intuit that the strategy is to us the index to scan the index `contact.fax` first, then filter the entries in the index by `contact.email`, it is neither clear that this is the case nor expected. One would expect that the index contains the list of documents under either of the keys, and therefore an AND query would hit the index key structure twice and do some nested loop join or something similar.

> I'm still seeking clarity on these technical points as of writing this document.

Let's try specifying three of the wildcard fields in the index, and see if things become any clearer:

```javascript
db.prospect.find({
  'contact.cell': '07404 190465',
  'contact.email': 'kagaje@what.not',
  'contact.fax': '01995 364874'
}).explain("queryPlanner")

```


The plan seems to imply the same general strategy. The index bounds only mention one of the three query terms, then the filter mentions the other two.

```javascript
"winningPlan": {
      "queryPlan": {
        "stage": "FETCH",
        "planNodeId": 2,
        "filter": {
          "$and": [
            {
              "contact.cell": {
                "$eq": "07404 190465"
              }
            },
            {
              "contact.fax": {
                "$eq": "01995 364874"
              }
            }
          ]
        },
        "inputStage": {
          "stage": "IXSCAN",
          "planNodeId": 1,
          "keyPattern": {
            "$_path": 1,
            "contact.email": 1,
            "status": 1
          },
          "indexName": "idx_compound_wild",
          "isMultiKey": false,
          "multiKeyPaths": {
            "$_path": [],
            "contact.email": [],
            "status": []
          },
          "isUnique": false,
          "isSparse": true,
          "isPartial": false,
          "indexVersion": 2,
          "direction": "forward",
          "indexBounds": {
            "$_path": [
              "[\"contact.email\", \"contact.email\"]"
            ],
            "contact.email": [
              "[\"kagaje@what.not\", \"kagaje@what.not\"]"
            ],
            "status": [
              "[MinKey, MaxKey]"
            ]
          }
        }
      },
      "slotBasedPlan": {
        "slots": "$$RESULT=s11 env: { s3 = 1695077542823 (NOW), s6 = KS(3C636F6E746163742E656D61696C003C6B6167616A6540776861742E6E6F7400F0FE04), s1 = TimeZoneDatabase(America/Grenada...Pacific/Efate) (timeZoneDB), s10 = {\"$_path\" : 1, \"contact.email\" : 1, \"status\" : 1}, s2 = Nothing (SEARCH_META), s5 = KS(3C636F6E746163742E656D61696C003C6B6167616A6540776861742E6E6F74000A0104), s14 = \"07404 190465\", s15 = \"01995 364874\" }",
        "stages": "[2] filter {(traverseF(s13, lambda(l1.0) { traverseF(getField(l1.0, \"cell\"), lambda(l2.0) { ((l2.0 == s14) ?: false) }, false) }, false) && traverseF(s13, lambda(l3.0) { traverseF(getField(l3.0, \"fax\"), lambda(l4.0) { ((l4.0 == s15) ?: false) }, false) }, false))} \n[2] nlj inner [] [s4, s7, s8, s9, s10] \n    left \n        [1] cfilter {(exists(s5) && exists(s6))} \n        [1] ixseek s5 s6 s9 s4 s7 s8 [] @\"6b0fb303-555b-449b-9877-faf4ac65459d\" @\"idx_compound_wild\" true \n    right \n        [2] limit 1 \n        [2] seek s4 s11 s12 s7 s8 s9 s10 [s13 = contact] @\"6b0fb303-555b-449b-9877-faf4ac65459d\" true false \n"
      }
    }
```

Alas, neither `db.prospect.stats()` nor `db.prospect.aggregate([{$indexStats:{}}}])` seemed to illuminate this further.
