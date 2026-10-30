# Model artwork

The composer uses the maker artwork from the Rails app’s
`app/assets/images/providers/`, copied on 2026-10-30. These are the same
logos used by the web model picker, not inference-host branding.

iOS asset catalogs retain the SVG source. Regenerate Android artwork from the corresponding
SVG with `rsvg-convert -w 96 -h 96 provider.svg -o model_provider.png`.
Keep the original aspect ratio and transparent background. OpenAI, Qwen and
xAI follow the web’s `invertIcon` flag; all other artwork keeps its colors.

The bridge’s stable `iconName` chooses only known bundled assets. Unknown
names are left out instead of fetching an arbitrary remote image.
