import zipfile, xml.etree.ElementTree as ET
from pathlib import Path
p = Path.home() / 'Desktop' / '鸿蒙和小车通信协议.xlsx'
print('EXISTS', p.exists())
with zipfile.ZipFile(p, 'r') as z:
    names = z.namelist()
    print('FILES', len(names))
    for n in names:
        if 'workbook' in n or 'sheet' in n or 'sharedStrings' in n:
            print(n)
