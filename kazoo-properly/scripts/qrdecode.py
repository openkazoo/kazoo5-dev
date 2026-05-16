#!/usr/bin/env python3

import sys
from pyzbar import pyzbar
import cv2

image = cv2.imread(sys.argv[1])

barcodes = pyzbar.decode(image)

for barcode in barcodes:
    print(barcode.data.decode("utf-8"))
