document.addEventListener('click', e => {
  const t = e.target.closest('[data-scrollto]');
  if(!t) return;
  e.preventDefault();
  const id = t.getAttribute('data-scrollto');
  const el = document.getElementById(id);
  if(el){ el.scrollIntoView({behavior:'smooth', block:'start'}); }
});
