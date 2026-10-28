// Home: a username box that opens /u/<username>.
document.getElementById("find").addEventListener("submit", (event) => {
  event.preventDefault();
  const name = document.getElementById("name").value.trim().replace(/^@/, "").toLowerCase();
  if (/^[a-z0-9_]{3,20}$/.test(name)) location.href = `/u/${name}`;
});
