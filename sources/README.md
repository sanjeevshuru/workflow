# sources/

Put the project documents here. The requirements-analyst only reads what is in this folder.

```
sources/
├── INDEX.md     ← one row per document (keep it updated)
├── brd/         business requirement documents
├── prd/         product requirement documents
└── techspec/    technical specifications
```

## Format (best first)
1. **Markdown (`.md`)** with real headings (`#`, `##`). The analyst finds sections by heading and cites them as `path#Heading`.
2. **PDF**. Works; the analyst reads only the relevant pages. Keep the text selectable, not scanned images.
3. **Word or Google Docs**: export to `.md` or `.pdf` first. `.docx` is not read reliably by every tool.

## Naming
`<module>-<short-title>-v<version>.md`, for example `prd/orders-bulk-upload-v2.md`. Keep old versions only if they still matter, and mark them `superseded` in INDEX.md.

Figma links inside documents are picked up too (see `flow/playbooks/figma.md`).
