#!/bin/bash
set -e

# Configuration - Customize these for your site
SITE_TITLE="Ari Logan's Blog"
SITE_URL="https://blog.arilogan.com"
SITE_DESC="Ari Logan's IT internship daily blog"
FEED_FILE="feed.xml"
INDEX_FILE="index.html"

# Step 1: Gather post details from user
echo "--- Create & Deploy New Blog Post ---"
read -p "Enter post title: " POST_TITLE
read -p "Enter filename (e.g., my-first-post): " FILENAME
echo "Enter post content (Press Enter, then Ctrl+D when finished):"
POST_CONTENT=$(cat)

# Set file paths and URLs
FILE_PATH="blog/${FILENAME}.html"
POST_URL="${SITE_URL}/${FILE_PATH}"
mkdir -p blog

# Simple HTML-escaping so stray &, <, >, " in titles/content can't break the markup
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    printf '%s' "$s"
}

ESC_TITLE=$(html_escape "$POST_TITLE")
ESC_CONTENT=$(html_escape "$POST_CONTENT")

# Step 2: Generate the HTML blog post
cat <<EOF > "$FILE_PATH"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${ESC_TITLE} | ${SITE_TITLE}</title>
</head>
<body>
    <article>
        <h1>${ESC_TITLE}</h1>
        <p><small>Published: $(date +"%B %d, %Y")</small></p>
        <hr>
        <div>
            ${ESC_CONTENT//$'\n'/<br>}
        </div>
        <p><a href="${SITE_URL}/index.html">← Back Home</a></p>
    </article>
</body>
</html>
EOF
echo "✓ Created HTML post at: $FILE_PATH"

# Step 3 & 4: Insert the new item into feed.xml and rebuild index.html
# Done with Python's xml.etree so escaping is always correct and the
# insertion can never silently fail the way the old sed-based "a" command did.
SITE_TITLE="$SITE_TITLE" SITE_URL="$SITE_URL" SITE_DESC="$SITE_DESC" \
FEED_FILE="$FEED_FILE" INDEX_FILE="$INDEX_FILE" \
POST_TITLE="$POST_TITLE" POST_URL="$POST_URL" POST_CONTENT="$POST_CONTENT" \
python3 <<'PYEOF'
import os
import xml.etree.ElementTree as ET
from email.utils import formatdate

feed_file = os.environ['FEED_FILE']
index_file = os.environ['INDEX_FILE']
site_title = os.environ['SITE_TITLE']
site_url = os.environ['SITE_URL']
site_desc = os.environ['SITE_DESC']
post_title = os.environ['POST_TITLE']
post_url = os.environ['POST_URL']
post_desc = ' '.join(os.environ['POST_CONTENT'].split())

ATOM_NS = 'http://www.w3.org/2005/Atom'
ET.register_namespace('atom', ATOM_NS)

if os.path.exists(feed_file):
    tree = ET.parse(feed_file)
    root = tree.getroot()
    channel = root.find('channel')
else:
    root = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = site_title
    ET.SubElement(channel, 'link').text = site_url + '/'
    ET.SubElement(channel, 'description').text = site_desc
    ET.SubElement(channel, 'language').text = 'en-us'
    atom_link = ET.SubElement(channel, f'{{{ATOM_NS}}}link')
    atom_link.set('href', f'{site_url}/{feed_file}')
    atom_link.set('rel', 'self')
    atom_link.set('type', 'application/rss+xml')
    tree = ET.ElementTree(root)

item = ET.Element('item')
ET.SubElement(item, 'title').text = post_title
ET.SubElement(item, 'link').text = post_url
ET.SubElement(item, 'description').text = post_desc
ET.SubElement(item, 'pubDate').text = formatdate()
ET.SubElement(item, 'guid').text = post_url

# Insert newest post as the first <item> (after channel metadata, before older items)
children = list(channel)
insert_idx = len(children)
for i, c in enumerate(children):
    if c.tag == 'item':
        insert_idx = i
        break
channel.insert(insert_idx, item)

ET.indent(tree, space='  ')
tree.write(feed_file, encoding='UTF-8', xml_declaration=True)
with open(feed_file, 'a') as f:
    f.write('\n')

DIRECTIVE_ESCAPE = str.maketrans({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'})

def esc(s):
    return (s or '').translate(DIRECTIVE_ESCAPE)

# Rebuild index.html from the now-authoritative feed.xml
items = channel.findall('item')
list_html = '\n'.join(
    f'            <li><a href="{esc(it.find("link").text)}">{esc(it.find("title").text)}</a></li>'
    for it in items
)

index_html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{site_title}</title>
</head>
<body>
    <header>
        <h1>{site_title}</h1>
        <p>{site_desc}</p>
        <p><a href="{site_url}/{feed_file}">Subscribe via RSS Feed</a></p>
    </header>
    <main>
        <h2>Recent Posts</h2>
        <ul>
{list_html}
        </ul>
    </main>
</body>
</html>
'''

with open(index_file, 'w') as f:
    f.write(index_html)

print(f"✓ Updated RSS feed at: {feed_file}")
print(f"✓ Rebuilt {index_file} with all post history")
PYEOF

# Step 5: Git automation and deploy to GitHub Pages
echo "Deploying updates to GitHub..."
git add blog/ "$FEED_FILE" "$INDEX_FILE"
git commit -m "Automated publish: ${POST_TITLE}"
git push origin main # Change 'main' to your master branch if using an older repo setup

echo "Success! Your site is live and the RSS feed is updated."
