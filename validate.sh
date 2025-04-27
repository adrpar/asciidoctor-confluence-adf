#!/bin/bash

schema_file="./adf.json"
data_file="./docs/asciidoc/arc42.adf"

python3 - <<EOF
import json
import sys
from jsonschema import Draft7Validator

with open("$schema_file") as f:
    schema = json.load(f)

with open("$data_file") as f:
    data = json.load(f)

validator = Draft7Validator(schema)
errors = sorted(validator.iter_errors(data), key=lambda e: e.path)

if not errors:
    print("Validation successful.")
else:
    print(f"Validation failed with {len(errors)} error(s):\n")
    for error in errors:
        path = ".".join(map(str, error.path)) or "(root)"
        print(f"- At '{path}': {error.message}")
    sys.exit(1)
EOF