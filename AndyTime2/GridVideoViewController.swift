//
//  GridVideoViewController.swift
//  AndyTime2
//
//  Created by Matt Donahoe on 7/4/23.
//

import UIKit
import AVFoundation

class GridVideoViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private var collectionView: UICollectionView!
    private var videoURLs: [URL] = [] // Array of video URLs
    private var nowPlaying: AVPlayer?
    
    init(videoURLs: [URL]) {
        self.videoURLs = videoURLs
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        self.view.backgroundColor = .red
    }
    
    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let itemSpacing: CGFloat = 10
        let numberOfItemsPerRow: CGFloat = 3
        
        let totalSpacing = itemSpacing * (numberOfItemsPerRow - 1)
        let itemWidth = (view.bounds.width - totalSpacing) / numberOfItemsPerRow
        let itemHeight = itemWidth
        
        layout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: "VideoCell")
        collectionView.backgroundColor = .white
        
        view.addSubview(collectionView)
    }
    
    // MARK: - UICollectionViewDataSource
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        print("count \(videoURLs.count)")
        return videoURLs.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoCell", for: indexPath) as! VideoCell
        
        // Configure the cell with video URL
        let videoURL = videoURLs[indexPath.item]
        cell.configure(with: videoURL)
        print("videoUrl = \(videoURL)")
        return cell
    }
    
    // MARK: - UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        nowPlaying?.pause()
        nowPlaying?.seek(to: .zero)
        let cell = collectionView.cellForItem(at: indexPath) as! VideoCell
        nowPlaying = cell.play()
        print("play")
    }
}

class VideoCell: UICollectionViewCell {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    override func prepareForReuse() {
        super.prepareForReuse()
        print("prep reuse")

        // Reset cell when reusing
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
    }
    
    func configure(with videoURL: URL) {
        print("configure with \(videoURL)")
        // Create an AVPlayer with the video URL
        player = AVPlayer(url: videoURL)
        
        // Create a player layer for video rendering
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = contentView.bounds
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.frame = contentView.bounds
        playerLayer?.isHidden = false

        contentView.layer.addSublayer(playerLayer!)
        
        // Pause the player
        player?.pause()
        player?.seek(to: .zero)
        
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.black.cgColor
    }
    
    func play() -> AVPlayer? {
        print("play")
        player?.seek(to: CMTime.zero)
        player?.play()
        playerLayer?.isHidden = false
        return player
    }
}
