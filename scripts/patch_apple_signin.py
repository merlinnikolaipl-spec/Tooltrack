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
    login_class = src.find('class _LoginPageState')
    if login_class < 0:
        print('ERROR: _LoginPageState not found!')
        sys.exit(1)
    print('_LoginPageState at', login_class)
    build_marker = src.find('@override', login_class)
    while build_marker >= 0:
        rest = src[build_marker:]
        if 'Widget build' in rest[:100]:
            break
        build_marker = src.find('@override', build_marker + 9)
    if build_marker < 0:
        print('ERROR: Widget build not found in _LoginPageState!')
        sys.exit(1)
    print('@override Widget build at', build_marker)
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
    ins_pos = src.rfind(chr(10), 0, build_marker) + 1
    src = src[:ins_pos] + m + src[ins_pos:]
    print('Added _signInWithApple method before build()')
else:
    print('_signInWithApple already present')

# Step 3: Add Apple button after Google sign-in button
if 'Sign in with Apple' not in src:
    signin_call = src.find('googleSignIn.signIn()')
    if signin_call < 0:
        signin_call = src.find('GoogleSignIn().signIn()')
    if signin_call < 0:
        print('ERROR: googleSignIn.signIn() not found!')
        sys.exit(1)
    print('googleSignIn.signIn() at', signin_call)
    # Find the onPressed: before this call
    onpressed_pos = src.rfind('onPressed:', 0, signin_call)
    if onpressed_pos < 0:
        print('ERROR: onPressed not found before signIn call!')
        sys.exit(1)
    print('onPressed: at', onpressed_pos)
    # Find widget containing this onPressed - search backwards for any widget
    btn_types = ['OutlinedButton(', 'TextButton(', 'ElevatedButton(', 'GestureDetector(', 
                 'InkWell(', 'Container(', 'FilledButton(', 'MaterialButton(', 'SignInButton(']
    btn_start = -1
    btn_end = -1
    best_dist = 999999
    for btype in btn_types:
        pos = src.rfind(btype, 0, onpressed_pos)
        if pos >= 0 and (onpressed_pos - pos) < best_dist:
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
            if cp >= 0 and cp > onpressed_pos:
                best_dist = onpressed_pos - pos
                btn_start = pos
                btn_end = cp
                print('Found button', repr(btype), 'at', pos, '..', cp)
    if btn_start < 0:
        # Try finding any widget at the line of onPressed
        line_start = src.rfind(chr(10), 0, onpressed_pos) + 1
        line_indent = ''
        for ch in src[line_start:]:
            if ch == ' ':
                line_indent += ch
            else:
                break
        print('onPressed indent:', repr(line_indent))
        # Try to find parent by going up lines with less indent
        search_up = onpressed_pos
        while search_up > 0:
            prev_nl = src.rfind(chr(10), 0, search_up - 1)
            if prev_nl < 0:
                break
            line = src[prev_nl+1:search_up]
            curr_indent = ''
            for ch in line:
                if ch == ' ':
                    curr_indent += ch
                else:
                    break
            if len(curr_indent) < len(line_indent) and line.strip().endswith('('):
                # Found a line with less indent ending with (
                btn_start = prev_nl + 1 + len(curr_indent)
                # This widget name starts here - find its (
                paren_pos = src.find('(', btn_start)
                if paren_pos < 0:
                    break
                dep = 0
                cp = -1
                idx = paren_pos
                while idx < len(src):
                    if src[idx] == '(':
                        dep += 1
                    elif src[idx] == ')':
                        dep -= 1
                        if dep == 0:
                            cp = idx
                            break
                    idx += 1
                if cp >= 0 and cp > onpressed_pos:
                    btn_end = cp
                    print('Found parent widget via indent at', btn_start, '..', btn_end)
                    break
            search_up = prev_nl
    if btn_start < 0:
        print('ERROR: Cannot find Google sign-in button widget!')
        print('Context around onPressed:')
        print(repr(src[max(0,onpressed_pos-300):onpressed_pos+300]))
        sys.exit(1)
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
