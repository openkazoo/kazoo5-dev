#!/usr/bin/env python3

import importlib

pyzbar_spec = importlib.util.find_spec("pyzbar")
found = pyzbar_spec is not None
print(found)
