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

# Step 2: Add _signInWithApple method
if '_signInWithApple' not in src:
    # Print diagnostic info
    for pat in ['GoogleSignIn', 'google_sign_in', 'signIn']:
        i = src.find(pat)
        if i >= 0:
            print('Found', repr(pat), 'at', i, ':', repr(src[max(0,i-50):i+100]))
    # Try anchors
    call_idx = -1
    for a in ['GoogleSignIn().signIn()', 'GoogleSignIn(', 'signInWithGoogle', 'signIn(']:
        i = src.find(a)
        if i >= 0:
            call_idx = i
            print('Anchor', repr(a), 'at', call_idx)
            break
    if call_idx < 0:
        print('ERROR: No sign-in anchor found!')
        sys.exit(1)
    func_start = src.rfind('async {', 0, call_idx)
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
    close = src.find(chr(10) + fi + '}', call_idx)
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
    for pat in [r'onPressed:\s*_loading\s*\?\s*null\s*:\s*_\w*[Gg]oogle\w*,?', r'Sign in with Google']:
        bm = re.search(pat, src)
        if bm:
            print('Button found at', bm.start(), repr(src[bm.start():bm.end()]))
            ae = bm.end()
            cl = src.find(');', ae)
            if cl < 0:
                print('ERROR: button close not found!')
                sys.exit(1)
            ia = cl + 2
            el = src.rfind('ElevatedButton(', 0, ae)
            bi = '          '
            if el >= 0:
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
            break
    else:
        print('ERROR: Google button not found!')
        sys.exit(1)
else:
    print('Apple button already present')

open('lib/main.dart', 'w', encoding='utf-8').write(src)
print('SUCCESS: Sign in with Apple added!')
