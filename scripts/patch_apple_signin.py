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

# Step 2: Add _signInWithApple method to _LoginPageState class
if '_signInWithApple' not in src:
    # Find _LoginPageState class
    login_class = src.find('class _LoginPageState')
    if login_class < 0:
        print('ERROR: _LoginPageState not found!')
        sys.exit(1)
    print('_LoginPageState at', login_class)
    # Find @override\n  Widget build inside this class
    build_marker = src.find('@override', login_class)
    while build_marker >= 0:
        # Check if next non-whitespace is Widget build
        rest = src[build_marker:]
        if 'Widget build' in rest[:100]:
            break
        build_marker = src.find('@override', build_marker + 9)
    if build_marker < 0:
        print('ERROR: Widget build not found in _LoginPageState!')
        sys.exit(1)
    print('@override Widget build at', build_marker)
    # Determine indentation (2 spaces for class method)
    fi = '  '
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
       + fi + '}' + NL)
    # Insert before @override
    # Find the newline before @override
    ins_pos = src.rfind(chr(10), 0, build_marker) + 1
    src = src[:ins_pos] + m + src[ins_pos:]
    print('Added _signInWithApple method before build()')
else:
    print('_signInWithApple already present')

# Step 3: Add Apple button after Google sign-in button
if 'Sign in with Apple' not in src:
    # Find googleSignIn.signIn() call position
    signin_call = src.find('googleSignIn.signIn()')
    if signin_call < 0:
        signin_call = src.find('GoogleSignIn().signIn()')
    if signin_call < 0:
        print('ERROR: googleSignIn.signIn() not found!')
        sys.exit(1)
    print('googleSignIn.signIn() at', signin_call)
    # Find the button widget containing this call
    # Search backwards from signin_call for button types
    btn_types = ['OutlinedButton(', 'TextButton(', 'ElevatedButton(', 'GestureDetector(', 'InkWell(']
    btn_start = -1
    btn_end = -1
    best_dist = 999999
    for btype in btn_types:
        # Find last occurrence of this button type before the signIn call
        pos = src.rfind(btype, 0, signin_call)
        if pos >= 0 and (signin_call - pos) < best_dist:
            # Verify this button contains the signIn call by finding its end
            dep = 0
            cp = -1
            idx = pos
            while idx < len(src):
                if src[idx] == '(':
                    dep += 1
                elif src[idx] == ')':
                    dep -= 1
                    if dep == 0:
                        cp = idx
                        break
                idx += 1
            if cp >= 0 and cp > signin_call:
                best_dist = signin_call - pos
                btn_start = pos
                btn_end = cp
                print('Found button', repr(btype), 'at', pos, '..', cp, '(dist', signin_call - pos, ')')
    if btn_start < 0:
        print('ERROR: No button containing googleSignIn.signIn() found!')
        sys.exit(1)
    # Insert Apple button after btn_end
    ia = btn_end + 1
    if ia < len(src) and src[ia] == ',':
        ia += 1
    print('Insert Apple button after pos', ia)
    ls = src.rfind(chr(10), 0, btn_start) + 1
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
