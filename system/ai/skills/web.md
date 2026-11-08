---
name: web
when: The person wants to search, look something up, open a website, watch or read something online, or use a site (YouTube, maps, shopping, mail).
---
# The web

Two different jobs; pick the right one.

**The person wants to SEE it** ("open the browser and search animals", "show me cat videos", "open YouTube"):
- One call: `browse(search="animals")` or `browse(url="https://youtube.com/results?search_query=cats")`.
  It opens the Browser already on the results and brings it to the front. Done. Do not open the
  browser and then type: the search is in the address you open.
- Useful addresses: Google `https://www.google.com/search?q=…`, images `…&tbm=isch`, YouTube
  `https://www.youtube.com/results?search_query=…`, Maps `https://www.google.com/maps/search/…`,
  Wikipedia `https://en.wikipedia.org/wiki/Special:Search?search=…` (use the person's language
  edition when they write in another language, e.g. ro.wikipedia.org).
- Afterwards say in one line what you opened. Don't describe the page unless asked.

**You need the information to answer** ("what's the capital…", "latest news on…", "price of…"):
- Use `web_search` / `web_fetch` when you have them (Claude), else `fetch_url` on a known page, and
  answer in the chat with the source. Don't open the browser for this unless asked.

**Doing something inside a page** (fill a form, click a button on a site):
1. `browse(url=…)`, then `wait_for_window(app="chromium")`.
2. `screenshot`, find the element, `click` it, `type_text(text=…, window="chromium")`.
3. To go to another address in the open browser: `press_keys("ctrl+l", window="chromium")`, then
   `type_text("address", window="chromium", enter=true)`.
4. Check with another `screenshot`. Never type passwords or payment details for the person;
   ask them to type those themselves. Stop and ask before buying, sending or posting anything.
