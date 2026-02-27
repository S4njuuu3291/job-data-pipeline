.PHONY: sync-main update-main help

sync-main:
	@echo "🔄 Syncing with main branch..."
	git checkout main
	git pull origin main
	@echo "✅ Sync complete!"

update-main: sync-main

help:
	@echo "Available commands:"
	@echo "  make sync-main     - Checkout main and pull latest changes"
	@echo "  make update-main   - Alias for sync-main"
