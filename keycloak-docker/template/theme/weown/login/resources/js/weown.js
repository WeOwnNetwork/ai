// Keycloak's login/register/reset-password templates never set placeholder
// text — an empty bordered box reads as an unstyled browser default no
// matter how the CSS dresses it up. This fills in a hint without forking
// the FTL templates themselves. Idempotent: never overwrites a placeholder
// a given flow's template already set.
document.addEventListener('DOMContentLoaded', function () {
  var user = document.getElementById('username');
  if (user && !user.placeholder && (user.type === 'text' || user.type === 'email')) {
    user.placeholder = 'you@company.com';
  }
  document.querySelectorAll('input[type="password"]').forEach(function (pw) {
    if (!pw.placeholder) pw.placeholder = '••••••••';
  });
});
