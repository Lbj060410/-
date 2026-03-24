"""Fix GBK->UTF8 mojibake in RecognitionScheduler.ets"""
import sys

FILE = 'F:/HarmonyOs/car/entry/src/main/ets/services/recognition/RecognitionScheduler.ets'

with open(FILE, 'rb') as f:
    data = f.read()

# Show lines around the problem areas
text = data.decode('utf-8', errors='replace')
lines = text.splitlines()
for i in range(55, 80):
    print(f'L{i+1}: {repr(lines[i])}')
