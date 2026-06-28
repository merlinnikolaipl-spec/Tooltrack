import sys

src = open('lib/main.dart', encoding='utf-8').read()
print('main.dart size:', len(src))

# Find ALL occurrences of GoogleSignIn
pos = 0
count = 0
while True:
    idx = src.find('GoogleSignIn', pos)
    if idx < 0:
        break
    count += 1
    print('--- GoogleSignIn occurrence', count, 'at pos', idx, '---')
    print(repr(src[max(0,idx-150):idx+200]))
    pos = idx + 12

print('Total occurrences:', count)

# Also find all ElevatedButton and show first 5 with context
print('\n=== ElevatedButton occurrences ===')
pos = 0
count2 = 0
while True:
    idx = src.find('ElevatedButton(', pos)
    if idx < 0:
        break
    count2 += 1
    if count2 <= 10:
        print('--- ElevatedButton', count2, 'at pos', idx, '---')
        print(repr(src[max(0,idx-100):idx+300]))
    pos = idx + 15

print('Total ElevatedButton:', count2)
