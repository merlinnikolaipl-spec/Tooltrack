import sys, re

# Patch main.dart: add Sign in with Apple alongside Google Sign-In
# Strategy:
#   1. Add sign_in_with_apple import to main.dart
#   2. Add _signInWithApple() method after _signInWithGoogle()
#   3. Add "Sign in with Apple" button in build() after Google button

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# ── Step 1: Add import ─────────────────────────────────────────────
google_import = "import 'package:google_sign_in/google_sign_in.dart';"
apple_import = "import 'package:sign_in_with_apple/sign_in_with_apple.dart';"

if apple_import in src:
    print('Apple import already present, skipping import step')
else:
    if google_import not in src:
        print('ERROR: Google Sign-In import not found!')
        sys.exit(1)
    src = src.replace(google_import, google_import + '\n' + apple_import, 1)
    print('Added sign_in_with_apple import')

# ── Step 2: Add _signInWithApple() method ─────────────────────────
if '_signInWithApple' in src:
    print('_signInWithApple already present, skipping method step')
else:
    # Find end of _signInWithGoogle method to insert after it
    anchor = '_signInWithGoogle() async {'
    anchor_idx = src.find(anchor)
    if anchor_idx < 0:
        print('ERROR: _signInWithGoogle not found!')
        sys.exit(1)
    # Find the closing brace of the method (look for "  }" at correct indent level)
    # The method is inside a State class, so it's indented with 2 spaces
    # Find "  Future<void> _sign" pattern to locate method start line
    line_start = src.rfind('\n', 0, anchor_idx) + 1
    indent = src[line_start:anchor_idx].replace('_signInWithGoogle() async {', '').rstrip()
    # Find closing } of the method: look for \n + indent + }
    close_pattern = '\n' + indent + '}'
    close_idx = src.find(close_pattern, anchor_idx)
    if close_idx < 0:
        print('ERROR: closing brace of _signInWithGoogle not found!')
        sys.exit(1)
    insert_pos = close_idx + len(close_pattern)
    print(f'Inserting _signInWithApple after pos {insert_pos}')
    
    apple_method = '''

  Future<void> _signInWithApple() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        setState(() { _errorMsg = e.message; });
      }
    } catch (e) {
      setState(() { _errorMsg = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }'''
    src = src[:insert_pos] + apple_method + src[insert_pos:]
    print('Added _signInWithApple() method')

# ── Step 3: Add Apple Sign-In button in UI ─────────────────────────
if 'Sign in with Apple' in src:
    print('Apple button already present, skipping UI step')
else:
    # Find the Google Sign-In ElevatedButton by its onPressed
    google_btn_anchor = 'onPressed: _loading ? null : _signInWithGoogle,'
    btn_idx = src.find(google_btn_anchor)
    if btn_idx < 0:
        # Try alternative
        google_btn_anchor = 'onPressed: _loading ? null : _signInWithGoogle'
        btn_idx = src.find(google_btn_anchor)
    if btn_idx < 0:
        print('ERROR: Google Sign-In button onPressed not found!')
        sys.exit(1)
    
    # Find the closing ) or ); of the ElevatedButton widget after the anchor
    # Look for the pattern that ends the button widget
    after_btn = src[btn_idx:]
    # Find next ); that closes ElevatedButton
    # ElevatedButton ends with its closing );
    close_btn = after_btn.find(');')
    if close_btn < 0:
        print('ERROR: Could not find end of Google button!')
        sys.exit(1)
    insert_after = btn_idx + close_btn + len(');')
    
    # Detect indentation from button line
    btn_line_start = src.rfind('\n', 0, btn_idx) + 1
    # Go back further to find the ElevatedButton( line
    elevated_idx = src.rfind('ElevatedButton(', 0, btn_idx)
    elevated_line_start = src.rfind('\n', 0, elevated_idx) + 1
    btn_indent = src[elevated_line_start:elevated_idx]
    
    apple_button = f"""
{btn_indent}const SizedBox(height: 12),
{btn_indent}ElevatedButton(
{btn_indent}  onPressed: _loading ? null : _signInWithApple,
{btn_indent}  style: ElevatedButton.styleFrom(
{btn_indent}    backgroundColor: Colors.black,
{btn_indent}    foregroundColor: Colors.white,
{btn_indent}    minimumSize: const Size.fromHeight(48),
{btn_indent}  ),
{btn_indent}  child: const Row(
{btn_indent}    mainAxisAlignment: MainAxisAlignment.center,
{btn_indent}    children: [
{btn_indent}      Icon(Icons.apple, size: 22),
{btn_indent}      SizedBox(width: 8),
{btn_indent}      Text('Sign in with Apple', style: TextStyle(fontSize: 16)),
{btn_indent}    ],
{btn_indent}  ),
{btn_indent}),"""
    
    src = src[:insert_after] + apple_button + src[insert_after:]
    print('Added Sign in with Apple button')

# ── Verify and write ───────────────────────────────────────────────
if '_signInWithApple' not in src or 'Sign in with Apple' not in src:
    print('ERROR: Verification failed - Apple sign-in not fully added!')
    sys.exit(1)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('SUCCESS: Sign in with Apple added to LoginPage!')
