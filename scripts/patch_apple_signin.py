import sys, re

# Patch main.dart: add Sign in with Apple alongside Google Sign-In
# v3: robust multi-anchor approach with diagnostics

with open('lib/main.dart', 'r', encoding='utf-8') as f:
        src = f.read()

print(f'main.dart size: {len(src)} chars')

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
    # Diagnostic: show all google-related patterns
        for pattern in ['GoogleSignIn', 'google_sign_in', 'signInWithGoogle', 'signInGoogle', 'google']:
                    idx = src.find(pattern)
                    if idx >= 0:
                                    print(f'Found {repr(pattern)} at {idx}: {repr(src[max(0,idx-50):idx+100])}')

                # Try multiple anchors for the Google sign-in call
                google_call_anchors = [
                            'GoogleSignIn().signIn()',
                            'GoogleSignIn(',
                            '_googleSignIn',
                            'signInWithGoogle',
                            'google_sign_in',
                ]
    call_idx = -1
    found_anchor = None
    for anchor in google_call_anchors:
                idx = src.find(anchor)
                if idx >= 0:
                                call_idx = idx
                                found_anchor = anchor
                                print(f'Found anchor {repr(anchor)} at {call_idx}')
                                break

            if call_idx < 0:
                        print('ERROR: No Google sign-in anchor found in main.dart!')
                        print('Searching for any Google-related content...')
                        for m in re.finditer(r'[Gg]oogle', src):
                                        ctx = src[max(0,m.start()-30):m.start()+80]
                                        print(f'  pos {m.start()}: {repr(ctx)}')
                                    sys.exit(1)

    # Find the async function containing the anchor
    func_start = src.rfind('\nasync {', 0, call_idx)
    if func_start < 0:
                func_start = src.rfind('async {', 0, call_idx)
    if func_start < 0:
                # Try async without space before {
                func_start = src.rfind('async{', 0, call_idx)
    print(f'async{{ found at {func_start}')

    # Find the function's indent
    func_line_start = src.rfind('\n', 0, func_start) + 1
    func_indent = ''
    for ch in src[func_line_start:]:
                if ch in (' ', '\t'):
                                func_indent += ch
else:
            break
    print(f'Function indent: {repr(func_indent)}')

    if not func_indent:
                func_indent = '  '  # fallback 2 spaces

    # Find closing } of the function after the anchor
    close_pattern = '\n' + func_indent + '}'
    close_idx = src.find(close_pattern, call_idx)
    if close_idx < 0:
                print(f'ERROR: closing brace not found with indent {repr(func_indent)}!')
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
    # Try multiple patterns to find the Google sign-in button
        google_btn_patterns = [
                    r'onPressed:\s*_loading\s*\?\s*null\s*:\s*_\w*[Gg]oogle\w*,?',
                    r'onPressed:\s*\(\)\s*=>\s*\w*[Gg]oogle\w*\(\)',
                    r'onPressed:\s*_loading\s*\?\s*null\s*:\s*\w*[Gg]oogle\w*',
                    r'Sign in with Google',
                    r'Google',
        ]
    google_btn_match = None
    for pat in google_btn_patterns:
                m = re.search(pat, src)
        if m:
                        google_btn_match = m
            print(f'Google button found with pattern {repr(pat)} at {m.start()}')
            print(f'  Match: {repr(src[m.start():m.end()])}')
            break

    if not google_btn_match:
                print('ERROR: Google Sign-In button not found with any pattern!')
        sys.exit(1)

    btn_anchor_end = google_btn_match.end()

    # Find the closing ); of the ElevatedButton/TextButton widget
    after_btn = src[btn_anchor_end:]
    close_btn = after_btn.find(');')
    if close_btn < 0:
                print('ERROR: Could not find end of Google button!')
        sys.exit(1)
    insert_after = btn_anchor_end + close_btn + len(');')

    # Detect indentation from widget line
    elevated_idx = src.rfind('\nElevatedButton(', 0, btn_anchor_end)
    if elevated_idx < 0:
                elevated_idx = src.rfind('\n  ElevatedButton(', 0, btn_anchor_end)
    if elevated_idx < 0:
                elevated_idx = src.rfind('\nOutlinedButton(', 0, btn_anchor_end)
    if elevated_idx < 0:
                elevated_idx = src.rfind('\nTextButton(', 0, btn_anchor_end)

    if elevated_idx >= 0:
                btn_line_start = elevated_idx + 1
        btn_indent = ''
        for ch in src[btn_line_start:]:
                        if ch in (' ', '\t'):
                                            btn_indent += ch
else:
                break
        print(f'Button indent: {repr(btn_indent)}')
else:
        btn_indent = '          '
        print(f'Using fallback button indent: {repr(btn_indent)}')

    inner = btn_indent + '  '
    apple_button = f"""
    {btn_indent}const SizedBox(height: 12),
    {btn_indent}ElevatedButton(
    {inner}style: ElevatedButton.styleFrom(
    {inner}  backgroundColor: Colors.black,
    {inner}  foregroundColor: Colors.white,
    {inner}  minimumSize: const Size(double.infinity, 48),
    {inner}),
    {inner}onPressed: _loading ? null : _signInWithApple,
    {inner}child: const Text('Sign in with Apple'),
    {btn_indent}),"""
    src = src[:insert_after] + apple_button + src[insert_after:]
    print('Added Sign in with Apple button')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
        f.write(src)
print('SUCCESS: Sign in with Apple added to LoginPage!')
