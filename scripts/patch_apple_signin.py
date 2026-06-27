import sys, re

# Patch main.dart: add Sign in with Apple alongside Google Sign-In
# v2: use GoogleSignIn().signIn() as anchor (not function name, which may vary)

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
    # Find the async function that calls GoogleSignIn().signIn()
    # Anchor: the line with GoogleSignIn().signIn() 
    google_call = 'GoogleSignIn().signIn()'
    call_idx = src.find(google_call)
    if call_idx < 0:
        print('ERROR: GoogleSignIn().signIn() not found!')
        sys.exit(1)
    print(f'GoogleSignIn().signIn() found at {call_idx}')
    
    # Find the closing } of this async function
    # The function body ends with: \n + indent + } where indent matches the function def
    # Look backward from call_idx to find the function definition line
    func_start = src.rfind('\nasync {', 0, call_idx)
    if func_start < 0:
        func_start = src.rfind('async {', 0, call_idx)
    print(f'async {{ found at {func_start}')
    
    # Find the function's indent: go to start of that line
    func_line_start = src.rfind('\n', 0, func_start) + 1
    func_indent = ''
    for ch in src[func_line_start:]:
        if ch in (' ', '\t'):
            func_indent += ch
        else:
            break
    print(f'Function indent: {repr(func_indent)}')
    
    # Find closing } of the function after the call
    close_pattern = '\n' + func_indent + '}'
    close_idx = src.find(close_pattern, call_idx)
    if close_idx < 0:
        print('ERROR: closing brace of Google function not found!')
        sys.exit(1)
    insert_pos = close_idx + len(close_pattern)
    print(f'Inserting _signInWithApple after pos {insert_pos}')
    
    inner_indent = func_indent + '  '
    apple_method = f"""

{func_indent}Future<void> _signInWithApple() async {{
{inner_indent}setState(() {{ _loading = true; _errorMsg = null; }});
{inner_indent}try {{
{inner_indent}  final appleCredential = await SignInWithApple.getAppleIDCredential(
{inner_indent}    scopes: [
{inner_indent}      AppleIDAuthorizationScopes.email,
{inner_indent}      AppleIDAuthorizationScopes.fullName,
{inner_indent}    ],
{inner_indent}  );
{inner_indent}  final oauthCredential = OAuthProvider('apple.com').credential(
{inner_indent}    idToken: appleCredential.identityToken,
{inner_indent}    accessToken: appleCredential.authorizationCode,
{inner_indent}  );
{inner_indent}  await FirebaseAuth.instance.signInWithCredential(oauthCredential);
{inner_indent}}} on SignInWithAppleAuthorizationException catch (e) {{
{inner_indent}  if (e.code != AuthorizationErrorCode.canceled) {{
{inner_indent}    setState(() {{ _errorMsg = e.message; }});
{inner_indent}  }}
{inner_indent}}} catch (e) {{
{inner_indent}  setState(() {{ _errorMsg = e.toString(); }});
{inner_indent}}} finally {{
{inner_indent}  setState(() {{ _loading = false; }});
{inner_indent}}}
{func_indent}}}"""
    src = src[:insert_pos] + apple_method + src[insert_pos:]
    print('Added _signInWithApple() method')

# ── Step 3: Add Apple Sign-In button in UI ─────────────────────────
if 'Sign in with Apple' in src:
    print('Apple button already present, skipping UI step')
else:
    # Find the onPressed that calls the Google sign-in function
    # Pattern: onPressed: _loading ? null : _signInWith...Google... 
    # Use regex to find it regardless of exact function name
    import re
    google_btn_match = re.search(r'onPressed:\s*_loading\s*\?\s*null\s*:\s*_\w*[Gg]oogle\w*,?', src)
    if not google_btn_match:
        print('ERROR: Google Sign-In button onPressed not found!')
        # Show context around GoogleSignIn().signIn() for debugging
        ci = src.find('GoogleSignIn().signIn()')
        print('Context:', repr(src[max(0,ci-200):ci+100]))
        sys.exit(1)
    
    btn_anchor_end = google_btn_match.end()
    print(f'Google button onPressed found at {google_btn_match.start()}')
    
    # Find the closing ); of the ElevatedButton widget 
    after_btn = src[btn_anchor_end:]
    close_btn = after_btn.find(');')
    if close_btn < 0:
        print('ERROR: Could not find end of Google button!')
        sys.exit(1)
    insert_after = btn_anchor_end + close_btn + len(');')
    
    # Detect indentation from ElevatedButton line
    elevated_idx = src.rfind('ElevatedButton(', 0, btn_anchor_end)
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
