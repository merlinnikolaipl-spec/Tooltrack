## Android — Current Status (as of 2026-07-18)

### Latest release: build 23 (version 1.1.1)

This document summarizes what was done to get the Android app through Google Play review, for context in future chat sessions.

### 1. Fixes applied before first submission

- targetSdkVersion raised to 35 (required by Play Console policy).
- - Declared location permissions (foreground + background) in Play Console app content declarations, matching the actual use case: GPS is used during shift check-in/check-out (including background) to confirm worker presence at an assigned construction site.
  - - Dismissed the 16KB native page size warning (non-blocking, acknowledged via override).
    - - Build number conflicts from earlier failed uploads were resolved by incrementing to a fresh, unused version code (23).
     
      - ### 2. First submission and rejection
     
      - - Release was saved and submitted for review successfully.
        - - On 2026-07-17 Google rejected the update. Policy Center showed: "Правила в отношении пользовательских данных: раздел 'Политика конфиденциальности'. Политика конфиденциальности не соответствует требованиям."
          - - Exact evidence from the issue details page: "LOCATION data is accessed by the app but not disclosed in privacy policy."
           
            - ### 3. Privacy policy fix
           
            - - Privacy policy is hosted externally on Google Sites, published at https://www.megabudalians.pl/polityka-prywatności (not in this repo).
              - - The page had no mention of location/GPS data at all before the fix.
                - - Added a new section "6. Dane o lokalizacji (GPS)" (in Polish, matching the rest of the page) disclosing: GPS is collected during shift start/end (check-in/check-out), including in the background, to confirm presence at the assigned site; data is used only for attendance verification and work-hour billing; stored in Google Firebase, not sold or shared with third parties beyond the Firebase infrastructure provider; user can disable location access in device settings at any time (this may limit shift-tracking functionality).
                  - - Page was republished on Google Sites and verified live.
                    - - Privacy Policy URL in Play Console (app-content/privacy-policy) was confirmed unchanged and correct — no edit needed there.
                     
                      - ### 4. Resubmission
                     
                      - - After the privacy policy fix, the pending release change ("build 23 — Начать полное внедрение / start full rollout") was saved and submitted for review again from Обзор публикации (Publishing overview).
                        - - Automated pre-check (common issues) passed with no errors.
                          - - Status as of this writing: "Изменения находятся на рассмотрении" (under review). Google re-checks the flagged privacy policy issue automatically on resubmission — no separate action needed in Policy Center.
                           
                            - ### 5. Tools list limit fix (Firestore)
                           
                            - - `_toolsStream` in `lib/main.dart` (StreamBuilder for the Инструменты/Tools page) previously had `.limit(200)`, which could hide tools beyond the first 200 per company.
                              - - Fixed 4 days ago via commit "Increase limit of tools stream from 200 to 5000".
                                - - Other related stream limits found in the same file (unchanged, considered acceptable for now): `_membersStream` limit 200, `_peopleStream` limit 200, `_movesStream` limit 200, sites list limit 100.
                                  - - Since `lib/main.dart` is shared Flutter code for both Android and iOS, this fix applies to both platforms once each platform is rebuilt from the current `main` branch.
                                   
                                    - ### 6. Release workflow reference (Play Console)
                                   
                                    - 1. Upload new build / bump version code in Play Console.
                                      2. 2. Fix any blocking errors shown in the pre-review check (targetSdk, permissions declarations, native page size, etc).
                                         3. 3. Save changes → "Перейти к обзору" (go to Publishing overview).
                                            4. 4. Click "Отправить N изменений на проверку" → confirm in the dialog.
                                               5. 5. If rejected: check notifications bell → "Подробнее" → Policy Center → click into the specific violation for exact evidence and solution steps.
                                                  6. 6. Fix the underlying issue (may be outside Play Console, e.g. an external privacy policy page).
                                                     7. 7. Return to Publishing overview, save/submit the pending change again to trigger re-review.
                                                        8. 
