# Native SMS login did not request CAS remember-me

User reports that the previous fixes work, but the app presents login again after
an overnight cold launch. The user confirms the original login used the native
SMS flow.

## Verified cause in the login request

Inspected the current public official CAS page at
`https://auth.ccsut.cn/backstage/cas/login` on 2026-10-26. The visible SMS checkbox
“记住账号” has Angular control `rememberUsername`. It saves the username locally;
it does not set the independent CAS `rememberMe` form control. The latter defaults
to false and has no visible checkbox in this deployed SMS form. The password tab
also exposes `rememberPassword`, a separate local credential-saving preference.

The official public bundle
`/backstage/cas/ng-login/main.80a7b1cf24378b9ae748.js` confirms that `postLogin`
uses rememberUsername/rememberPassword for local storage and generates an actual
POST form containing `rememberMe`. It calls native `form.submit()`, bypassing
DOM submit events.

Executed the unchanged production `LoginView.script` on the real official page
with dummy account/code values. Replaced the native form submit sink with a
recorder before execution, so **no login POST, SMS send or real credentials were
sent**. The resulting form had method POST, path `/backstage/cas/login`, and
`rememberMe=false`, despite the existing script clicking “记住账号”.

## Scoped fix and verification

`WebFactory` installs a main-frame document-start WKUserScript for the official
HTTPS CAS login page. It sets the existing generated `rememberMe` field to true
immediately before native form submission, preserving the official submit call.
The capture-phase submit listener also covers ordinary submit/requestSubmit.
Other hosts, paths, GET forms, credential-bearing action URLs and forms without
this field are untouched. It neither stores passwords nor retries login requests.

- Targeted Node regression first failed because rememberMe remained false.
- With the production script installed, all targeted assertions pass, including
  form scope, event submission and no duplicate POST from repeated installation.
- Repeated the same real-page/native-SMS-script interception: POST to the same CAS
  path now contains `rememberMe=true`. No login request left the browser.
- Dedicated disposable browser closed after inspection.
- No full test suite was run, per the user's instruction.

## Acceptance boundary

This proves a missing persistent-login request parameter and its correction. It
does not establish the school's actual remember-me session lifetime, nor prove
that this is the only cause of the observed overnight logout. Existing issued
sessions cannot be made persistent retroactively: a new login with the updated
app is required. Overnight physical-device acceptance remains pending. Keychain
cookie storage, native bootstrap/CAS renewal and the previous campus SPA redirect
fix remain unchanged.
