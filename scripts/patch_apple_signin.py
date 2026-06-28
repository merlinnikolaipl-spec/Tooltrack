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
    anchor = '_signInWithGoogle'
    anchor_idx = src.find(anchor)
    if anchor_idx < 0:
        for a in ['signInWithGoogle', 'GoogleSignIn().signIn()', 'GoogleSignIn(']:
            anchor_idx = src.find(a)
            if anchor_idx >= 0:
                print('Anchor', repr(a), 'at', anchor_idx)
                break
    else:
        print('Anchor _signInWithGoogle at', anchor_idx)
    if anchor_idx < 0:
        print('ERROR: No sign-in anchor found!')
        sys.exit(1)
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

# Step 3: Add Apple button
if 'Sign in with Apple' not in src:
    btn_patterns = [
        r'onPressed:\s*_loading\s*\?\s*null\s*:\s*_signInWithGoogle',
        r'onPressed:\s*_loading\s*\?\s*null\s*:\s*_\w*[Gg]oogle\w*',
        r"child:\s*(?:const\s+)?Text\(['\"]Sign in with Google['\"]",
    ]
    bm = None
    for pat in btn_patterns:
        bm = re.search(pat, src)
        if bm:
            print('Button found with pattern', repr(pat), 'at', bm.start())
            break
    if not bm:
        print('ERROR: Google Sign-In button not found!')
        sys.exit(1)
    el = src.rfind('ElevatedButton(', 0, bm.start())
    if el < 0:
        print('ERROR: ElevatedButton not found before pattern!')
        sys.exit(1)
    print('ElevatedButton at', el)
    depth = 0
    close_pos = -1
    i = el
    while i < len(src):
        if src[i] == '(':
            depth += 1
        elif src[i] == ')':
            depth -= 1
            if depth == 0:
                close_pos = i
                break
        i += 1
    if close_pos < 0:
        print('ERROR: ElevatedButton close paren not found!')
        sys.exit(1)
    ia = close_pos + 1
    if ia < len(src) and src[ia] == ',':
        ia += 1
    print('Insert after pos', ia)
    ls = src.rfind(chr(10), 0, el) + 1
    bi = ''
    for ch in src[ls:]:
        if ch == ' ':
            bi += ch
        else:
            break
    print('btn_indent:', repr(bi))
    NL = chr(10)
    ii2 = bi + '  '
    btn = (NL + bi + 'const SizedBox(height: 12),' + NL
        + bi + 'ElevatedButton(' + NL
        + ii2 + 'style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48)),' + NL
        + ii2 + 'onPressed: _loading ? null : _signInWithApple,' + NL
        + ii2 + "child: const Text('Sign in with Apple')," + NL
        + bi + '),')
    src = src[:ia] + btn + src[ia:]
    print('Added Apple button')
else:
    print('Apple button already present')

open('lib/main.dart', 'w', encoding='utf-8').write(src)
print('SUCCESS: Sign in with Apple added!')
