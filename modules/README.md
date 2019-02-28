# Modules

Each directory here is to be a module of a specific test.  The main kickoff
of the module is to have the fixed name of **run** that performs the test.

# Output

The format is to be XML.  

## XML specification

Formal DTD forthcoming

```
<module>
  <name> ... </name>
  <result>(pass|fail|caution|unknown|info)</result>
  <reason> <-- May include subfields as needed to explain the result --> </reason>
  <number>(\d+)</number>
</module>
```

#### Name

The name is to be an arbitrary text string

#### Result

The result is to have the following meaning

| result | meaning |
|--------|---------|
| pass | All items as expected |
| fail | At least one item not as expected, details are in the result tag |
| caution | All items currently as expected, but something may soon change to failure |
| unknown | Unable to determine status automatically |
| info | This module is not a pass or fail class module |

#### Reason

This tag is a container for explaining the result.  It may be empty for 
items that pass.  Sub fields may exist, and are module specific, but the
base reason is to be an explanatory string.

#### Number

A unique numerical identifier for the module
