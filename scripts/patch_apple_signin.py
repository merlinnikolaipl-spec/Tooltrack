import sys, re

src = open('lib/main.dart', encoding='utf-8').read()
print('main.dart size:', len(src))

GOOGLE_IMPORT = "import 'package:google_sign_in/google_sign_in.dart';"
APPLE_IMPORT = "import 'package:sign_in_with_apple/sign_in_with_apple.dart';"

# Step 1: Add import
assert GOOGLE_IMPORT in src, 'ERROR: Google Sign-In import not found!'
if APPLE_IMPORT not in src:
    src = src.replace(GOOGLE_IMPORT, GOOGLE_IMPORT + chr(10) + APPLE_IMPORT, 1)
    print('Added sign_in_with_apple import')
else:
    print('Apple import already present')

# Step 2: Add _signInWithApple method after _signInWithGoogle method
if '_signInWithApple' not in src:
    anchor_idx = src.find('_signInWithGoogle')
    if anchor_idx < 0:
        anchor_idx = src.find('GoogleSignIn(')
        if anchor_idx >= 0:
            print('Anchor GoogleSignIn( at', anchor_idx)
        else:
            print('ERROR: No sign-in anchor found!')
            sys.exit(1)
    else:
        print('Anchor _signInWithGoogle at', anchor_idx)
    func_start = src.rfind('async {', 0, anchor_idx)
    if func_start < 0:
        func_start = src.rfind('async{', 0, anchor_idx)
    print('async{ at', func_start)
    func_line_start = src.rfind(chr(10), 0, func_start) + 1
    fi = ''
    for ch in src[func_line_start:]:
        if ch == ' ':
            fi += ch
        else:
            break
    if not fi:
        fi = '  '
    print('func_indent:', repr(fi))
    close = src.find(chr(10) + fi + '}', anchor_idx)
    if close < 0:
        print('ERROR: closing brace not found!')
        sys.exit(1)
    ins = close + len(chr(10) + fi + '}')
    NL = chr(10)
    ii = fi + '  '
    m = (NL + fi + 'Future<void> _signInWithApple() async {' + NL
       + ii + 'setState(() { _loading = true; _errorMsg = null; });' + NL
       + ii + 'try {' + NL
       + ii + "  final c = await SignInWithApple.getAppleIDCredential(scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]);" + NL
       + ii + "  final cred = OAuthProvider('apple.com').credential(idToken: c.identityToken, accessToken: c.authorizationCode);" + NL
       + ii + '  await FirebaseAuth.instance.signInWithCredential(cred);' + NL
       + ii + '} on SignInWithAppleAuthorizationException catch (e) {' + NL
       + ii + '  if (e.code != AuthorizationErrorCode.canceled) setState(() { _errorMsg = e.message; });' + NL
       + ii + '} catch (e) {' + NL
       + ii + '  setState(() { _errorMsg = e.toString(); });' + NL
       + ii + '} finally {' + NL
       + ii + '  setState(() { _loading = false; });' + NL
       + ii + '}' + NL
       + fi + '}')
    src = src[:ins] + m + src[ins:]
    print('Added _signInWithApple method')
else:
    print('_signInWithApple already present')

# Step 3: Find ElevatedButton containing GoogleSignIn and add Apple button after it
if 'Sign in with Apple' not in src:
    google_anchor = src.find('GoogleSignIn(')
    if google_anchor < 0:
        print('ERROR: Google anchor not found!')
        sys.exit(1)
    print('Google anchor at', google_anchor)
    # Search all ElevatedButton and find one containing GoogleSignIn
    search_pos = 0
    el = -1
    close_pos = -1
    while True:
        candidate = src.find('ElevatedButton(', search_pos)
        if candidate < 0:
            break
        dep = 0
        cp = -1
        idx = candidate
        while idx < len(src):
            if src[idx] == '(':
                dep += 1
            elif src[idx] == ')':
                dep -= 1
                if dep == 0:
                    cp = idx
                    break
            idx += 1
        if cp >= 0 and 'GoogleSignIn(' in src[candidate:cp+1]:
            el = candidate
            close_pos = cp
            print('Found Google ElevatedButton at', el)
            break
        search_pos = candidate + 15
    if el < 0:
        print('No ElevatedButton with GoogleSignIn found, trying OutlinedButton/TextButton')
        for btype in ['OutlinedButton(', 'TextButton(']:
            sp = 0
            while True:
                c2 = src.find(btype, sp)
                if c2 < 0:
                    break
                d2 = 0
                c2p = -1
                i2 = c2
                while i2 < len(src):
                    if src[i2] == '(':
                        d2 += 1
                    elif src[i2] == ')':
                        d2 -= 1
                        if d2 == 0:
                            c2p = i2
                            break
                    i2 += 1
                if c2p >= 0 and 'GoogleSignIn(' in src[c2:c2p+1]:
                    el = c2
                    close_pos = c2p
                    print('Found Google button', btype, 'at', el)
                    break
                sp = c2 + len(btype)
            if el >= 0:
                break
    if el < 0:
        print('ERROR: No button with GoogleSignIn found!')
        # Diagnostic: show context around GoogleSignIn
        print(repr(src[max(0,google_anchor-200):google_anchor+500]))
        sys.exit(1)
    ia = close_pos + 1
    if ia < len(src) and src[ia] == ',':
        ia += 1
    print('Insert Apple button after pos', ia)
    ls = src.rfind(chr(10), 0, el) + 1
    bi = ''
    for ch in src[ls:]:
        if ch == ' ':
            bi += ch
        else:
            break
    if not bi:
        bi = '              '
    print('btn_indent:', repr(bi))
    NL = chr(10)
    apple_btn = (NL + bi + 'ElevatedButton(' + NL
               + bi + '  onPressed: _loading ? null : _signInWithApple,' + NL
               + bi + '  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48)),' + NL
               + bi + "  child: const Text('Sign in with Apple')," + NL
               + bi + '),')
    src = src[:ia] + apple_btn + src[ia:]
    print('Added Apple Sign-In button')
else:
    print('Apple button already present')

open('lib/main.dart', 'w', encoding='utf-8').write(src)
print('Done. New size:', len(src))
