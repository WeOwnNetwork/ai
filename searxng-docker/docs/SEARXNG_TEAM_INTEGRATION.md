# WeOwn SearXNG Team Integration Guide

This guide explains how team members can use the WeOwn private SearXNG search instance:

https://searxng.weown.app

SearXNG is a privacy-focused search front end. It lets the team search from one WeOwn-managed page instead of sending every search directly through a single public search provider.

## Who This Is For

This document is written for non-dev team members who want to:

- Open the WeOwn search page directly.
- Add WeOwn SearXNG as a browser search engine.
- Understand what IT/admins can automate later with Ansible.

## Use It Directly

Open this URL in your browser:

https://searxng.weown.app

You can bookmark it like any other site.

Recommended bookmark name:

```text
WeOwn Search
```

## Add It As A Search Engine

Use these values when your browser asks for a custom search engine:

```text
Name: WeOwn SearXNG
Shortcut / Keyword: weown
Search URL: https://searxng.weown.app/search?q=%s
```

Some browsers use `{searchTerms}` instead of `%s`. If your browser asks for that format, use:

```text
https://searxng.weown.app/search?q={searchTerms}
```

## Chrome Or Brave

1. Open browser settings.
2. Search for `Search engine`.
3. Open `Manage search engines and site search`.
4. Add a new site search entry.
5. Use:

```text
Search engine: WeOwn SearXNG
Shortcut: weown
URL with %s in place of query: https://searxng.weown.app/search?q=%s
```

After that, type this in the address bar:

```text
weown project update
```

If the browser recognizes the shortcut, it will search WeOwn SearXNG for `project update`.

## Microsoft Edge

1. Open Edge settings.
2. Go to `Privacy, search, and services`.
3. Open `Address bar and search`.
4. Open `Manage search engines`.
5. Add:

```text
Search engine: WeOwn SearXNG
Shortcut: weown
URL with %s in place of query: https://searxng.weown.app/search?q=%s
```

## Firefox

Firefox usually discovers SearXNG through OpenSearch.

1. Open https://searxng.weown.app.
2. Click the address bar.
3. Look for an option to add the search engine.
4. Add it as `WeOwn SearXNG`.

If Firefox does not show an add option, use the direct bookmark method above.

## Recommended Team Usage

- Use WeOwn SearXNG for general web research.
- Do not paste secrets, passwords, private keys, customer credentials, or confidential legal/finance data into any search engine.
- If a search result looks suspicious, open it carefully and avoid entering credentials.

## Admin Automation

Admins can configure supported browsers automatically with Ansible using:

```bash
ansible-playbook -i inventory-workstations.ini configure-searxng-browser-search.yml
```

Important:

- This playbook is for employee workstations or managed desktops.
- It is not for the SearXNG production servers.
- If Firefox is already managed by company policy, merge the Firefox `policies.json` section instead of overwriting the existing policy file.
- Review it in check mode first:

```bash
ansible-playbook -i inventory-workstations.ini configure-searxng-browser-search.yml --check
```

## Example Workstation Inventory

Linux workstations:

```ini
[linux_workstations]
alice-laptop ansible_host=10.0.1.20 ansible_user=admin
bob-desktop ansible_host=10.0.1.21 ansible_user=admin
```

Windows workstations require WinRM and the `ansible.windows` collection:

```ini
[windows_workstations]
frontdesk-pc ansible_host=10.0.2.15

[windows_workstations:vars]
ansible_connection=winrm
ansible_user=Administrator
ansible_password=REPLACE_ME
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
```

The included playbook configures Chrome, Edge, and Firefox policies where those browsers support managed search configuration.
