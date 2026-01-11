# Knowledge Repository

This repository contains your company's institutional knowledge, indexed by Atlas for AI-assisted planning and execution.

## Directory Structure

```
├── company/           # Company-level information
│   ├── vision.md      # Long-term vision and mission
│   ├── values.md      # Core values and principles
│   └── strategy.md    # Current strategic priorities
│
├── product/           # Product documentation
│   └── ...            # Product specs, roadmaps, user research
│
├── processes/         # Team processes and runbooks
│   └── ...            # How we do things
│
└── uploads/           # External documents (PDFs, etc.)
    └── ...            # Will be indexed by Atlas
```

## How Atlas Uses This Repository

Atlas indexes the content in this repository to provide context-aware AI assistance:

1. **Planning**: When creating plans, Atlas references your strategy and priorities
2. **Execution**: When implementing features, Atlas considers your values and processes
3. **Documentation**: Atlas understands your documentation style and standards

## Best Practices

### Keep Content Updated
- Review and update strategy quarterly
- Archive outdated processes
- Remove irrelevant documents

### Be Specific
- Concrete examples help AI agents make better decisions
- Include the "why" behind processes
- Document edge cases and exceptions

### Use Clear Structure
- Use headings and lists for scannability
- Keep documents focused on one topic
- Link related documents together

## Adding New Content

1. Choose the appropriate directory
2. Use markdown format when possible
3. Include context about when/why the document applies
4. Run `/atlas update-knowledge` to re-index

## Questions?

For help with Atlas configuration, run `/atlas setup` or see the [Atlas documentation](https://github.com/jack-services/atlas).
