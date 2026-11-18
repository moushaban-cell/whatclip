import AppKit
import WhatClipCore

/// The visual shelf: items as cards in a grid, with thumbnails, colour swatches and a titleLabel. Selecting a card selects the same
/// item in the list, so the details pane and the actions stay in one place.
@MainActor
/// The cards grid. Right-click on a card opens the same menu as a list row (edit, pin, favourite, delete).
final class ShelfCollectionView: NSCollectionView {
    var menuForIndex: ((Int) -> NSMenu?)?
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let ip = indexPathForItem(at: p), let menu = menuForIndex?(ip.item) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

@MainActor
final class ShelfController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let collection = ShelfCollectionView()
    /// Builds the right-click menu for the card at an index (set by the picker and the history window).
    var menuForItem: ((Int) -> NSMenu?)? { didSet { collection.menuForIndex = menuForItem } }
    /// A double-click on a card: the same as choosing the item (paste it).
    var onActivate: ((Int) -> Void)?
    let scroll = NSScrollView()
    var items: [ClipItem] = []
    var store: ClipStore?
    var onSelect: ((Int) -> Void)?

    override init() {
        super.init()
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 120)
        layout.minimumInteritemSpacing = 10; layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        collection.collectionViewLayout = layout
        collection.register(CardView.self, forItemWithIdentifier: CardView.identifier)
        collection.dataSource = self; collection.delegate = self
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.backgroundColors = [.textBackgroundColor]
        collection.setAccessibilityLabel("Clipboard cards")
        scroll.documentView = collection; scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
    }

    func reload(_ newItems: [ClipItem], store: ClipStore) {
        items = newItems; self.store = store
        collection.reloadData()
    }

    func select(_ indexes: Set<Int>) {
        collection.deselectAll(nil)
        collection.selectItems(at: Set(indexes.map { IndexPath(item: $0, section: 0) }), scrollPosition: .nearestHorizontalEdge)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: CardView.identifier, for: indexPath) as! CardView
        item.configure(items[indexPath.item], store: store)
        let index = indexPath.item
        item.onDoubleClick = { [weak self] in self?.onActivate?(index) }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        onSelect?(indexPaths.map(\.item).min() ?? 0)
    }
}

/// One card: a preview on top, the title and source under it.
/// The card's own surface: it sees its clicks, so a double-click on the card is recognised here.
final class CardSurface: NSView {
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)          // selects the card as before
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

final class CardView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("card")
    /// Set by the grid: runs when the card is double-clicked.
    var onDoubleClick: (() -> Void)? { didSet { (view as? CardSurface)?.onDoubleClick = onDoubleClick } }
    private let preview = NSView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let surface = CardSurface()
        surface.onDoubleClick = onDoubleClick
        view = surface
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.borderWidth = 1; view.layer?.borderColor = NSColor.separatorColor.cgColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium); titleLabel.maximumNumberOfLines = 2; titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 10); subtitleLabel.textColor = .secondaryLabelColor; subtitleLabel.lineBreakMode = .byTruncatingTail
        preview.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false; subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview); view.addSubview(titleLabel); view.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            preview.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderColor = isSelected ? Design.accent.cgColor : NSColor.separatorColor.cgColor
            view.layer?.borderWidth = isSelected ? 2 : 1
        }
    }

    func configure(_ item: ClipItem, store: ClipStore?) {
        preview.subviews.forEach { $0.removeFromSuperview() }
        let badge = Design.badge(for: item, store: store)
        badge.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(badge)
        NSLayoutConstraint.activate([badge.centerXAnchor.constraint(equalTo: preview.centerXAnchor), badge.centerYAnchor.constraint(equalTo: preview.centerYAnchor)])
        // Larger previews for images: fill the preview area.
        if let img = Design.thumbnail(item, store: store) { _ = img }
        titleLabel.stringValue = item.secretKinds.isEmpty ? PickerController.oneLine(item.listTitle) : "Hidden secret"
        subtitleLabel.stringValue = Design.appName(item.sourceBundleID) ?? item.kind.rawValue
    }
}
