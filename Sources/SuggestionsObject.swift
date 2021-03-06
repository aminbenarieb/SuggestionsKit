//
//  SuggestionsObject.swift
//  Suggestions
//
//  Created by huemae on 12.04.2020.
//  Copyright (c) 2020 huemae <ilyailusha@hotmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import UIKit


class SuggestionsObject: NSObject {
    
    enum Constant {
        static let spaceBetweenOverlayAndText: CGFloat = 10.0
        static let bubleOffset: CGFloat = 10.0
        static let minimalCornerRadius: CGFloat = 5.0
        static let holeOverdrawAmount: CGFloat = 10.0
        static let textDrawingSuperviewOffset: CGFloat = 20.0
    }
    
    private var fillLayer: FillLayer?
    private var bubleLayer: BubleLayer?
    private var textLayer: TextLayer?
    private var blurLayer: BlurLayer?
    private var unblurLayer: UnblurLayer?
    private var mainView: MainView?
    
    private var lastSuggested: Suggestion?
    
    private var holeRect: CGRect = .zero
    private var textLayerRect: CGRect = .zero
    private var holeMoveDuration: TimeInterval = 0
    private var hashTable: NSHashTable<NSKeyValueObservation> = NSHashTable()
    
    private var shouldTouchBeCounted = true
    
    private let config: SuggestionsConfig
    
    private var view: UIView {
        guard let view = mainView else { preconditionFailure("") }
        
        return view
    }
    
    private var layer: CALayer {
        guard let layer = mainView?.layer else { preconditionFailure("") }
        
        return layer
    }
    
    private var bounds: CGRect {
        guard let view = mainView else { preconditionFailure("") }
        
        return view.bounds
    }
    
    private var frame: CGRect {
        guard let view = mainView else { preconditionFailure("") }
        
        return view.frame
    }
    
    private var insets: UIEdgeInsets {
        guard let view = mainView else { preconditionFailure("") }
        
        if #available(iOS 11.0, *) {
            return view.safeAreaInsets
        } else {
            return UIEdgeInsets.zero
        }
    }
    
    private var canUseFilteredLayer: Bool = {
        return UIVisualEffectView.canUseFilteredLayer()
    }()
    
    var viewTappedBlock: (() -> ())?
    
    init(config: SuggestionsConfig) {
        self.config = config
        super.init()
        configure(with: config)
    }
    
    func suggestionsFinished() {
        mainView?.finish()
    }
    
    func updateForSuggestion(suggestion: Suggestion?) {
        if let suggestion = suggestion {
            startObserve(suggestion: suggestion)
            updateWithSuggestion(suggestion: suggestion)
            UIView.animate(withDuration: 1.0, animations: {
                self.mainView?.alpha = 1.0
            })
        } else {
            if config.hapticEnabled {
                if #available(iOS 10.0, *) {
                    let generator = UINotificationFeedbackGenerator()
                    generator.prepare()
                    generator.notificationOccurred(.success)
                }
            }
            suggestionsFinished()
        }
    }
    
    func perfromWithDelayAndCanceling() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performUpdateAfterBoundsChange), object: nil)
        perform(#selector(performUpdateAfterBoundsChange), with: nil, afterDelay: 0.0)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        perfromWithDelayAndCanceling()
    }
}

private extension SuggestionsObject {
    
    func lockViewInteraction(for seconds: TimeInterval) {
        shouldTouchBeCounted = false
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.shouldTouchBeCounted = true
        }
    }
    
    @objc func performUpdateAfterBoundsChange() {
        guard let suggestion = lastSuggested else { return }
        updateForSuggestion(suggestion: suggestion)
        blurLayer?.update(parent: layer, config: config)
        unblurLayer?.updateUnblur(suggestion: suggestion, holeRect: holeRect, animationDuration: holeMoveDuration)
    }
    
    func startObserve(suggestion: Suggestion) {
        lastSuggested = suggestion
        hashTable.removeAllObjects()
        let closure: ((CALayer, NSKeyValueObservedChange<CGRect>) -> Void) = { [weak self] la, value in
            self?.perfromWithDelayAndCanceling()
        }
        let closurePoint: ((CALayer, NSKeyValueObservedChange<CGPoint>) -> Void) = { [weak self] la, value in
            self?.perfromWithDelayAndCanceling()
        }
        let newObs = view.layer.observe(\.bounds, changeHandler: closure)
        let newObs1 = view.layer.observe(\.frame, changeHandler: closure)
        let newObs2 = view.layer.observe(\.position, changeHandler: closurePoint)
        let newObss = view.layer.superlayer?.observe(\.bounds, changeHandler: closure)
        let newObs11 = view.layer.superlayer?.observe(\.frame, changeHandler: closure)
        let newObs22 = view.layer.superlayer?.observe(\.position, changeHandler: closurePoint)
        hashTable.add(newObs)
        hashTable.add(newObs1)
        hashTable.add(newObs2)
        hashTable.add(newObss)
        hashTable.add(newObs11)
        hashTable.add(newObs22)
    }
    
    func removeObservingAtLastSuggested() {
    }
    
    func frame(of suggestion: Suggestion) -> CGRect {
        guard let superview = mainView?.superview, let view = suggestion.view else { return .zero }
        let newOrigin = view.convert(superview.frame, to: nil).origin
        return CGRect(x: newOrigin.x, y: newOrigin.y, width: view.frame.width, height: view.frame.height)
    }
    
    func maxWidthToDrawText() -> CGFloat {
        let bounds = boundsForDrawingText()
        return bounds.width - bounds.origin.x * 2
    }
    
    func boundsForDrawingText() -> CGRect {
        let offset = Constant.textDrawingSuperviewOffset
        return frame.inset(by: UIEdgeInsets(top: offset, left: offset, bottom: offset + insets.bottom, right: offset))
    }
    
    func updateText(suggestion: Suggestion) {
        textLayer?.update(boundsForDrawing: boundsForDrawingText(), maxTextWidth: maxWidthToDrawText(), suggestion: suggestion, animationDuration: holeMoveDuration)
    }
    
    func updateOverlay(suggestion: Suggestion) {
        fillLayer?.update(suggestion: suggestion, parentBounds: layer.bounds)
    }
    
    func updateBuble(of suggestion: Suggestion) {
        bubleLayer?.update(textRect: textLayerRect, holeRect: holeRect, suggestion: suggestion, animationDuration: holeMoveDuration)
    }
    
    func updateUnblur(suggestion: Suggestion) {
        unblurLayer?.update(frame: layer.bounds)
        unblurLayer?.updateUnblur(suggestion: suggestion, holeRect: holeRect, animationDuration: holeMoveDuration)
    }
    
    func updateWithSuggestion(suggestion: Suggestion) {
        updateOverlay(suggestion: suggestion)
        updateText(suggestion: suggestion)
        updateBuble(of: suggestion)
        updateUnblur(suggestion: suggestion)
    }
    
    @objc func viewTapped() {
        guard shouldTouchBeCounted else { return }
        if config.hapticEnabled {
            if #available(iOS 10.0, *) {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
        viewTappedBlock?()
    }
    
    func configureGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        view.addGestureRecognizer(tap)
        view.isUserInteractionEnabled = true
    }
    
    func configureAppearance() {
        view.backgroundColor = UIColor.clear
    }
    
    func configreDimmLayer(config: SuggestionsConfig) {
        
        let dimm = FillLayer(parent: layer, config: config)
        dimm.holeMoveDurationUpdatedClosue = { [weak self] duration in
            self?.holeMoveDuration = duration
            self?.lockViewInteraction(for: duration)
        }
        
        dimm.holeRectUpdatedClosue = { [weak self] newRect in
            self?.holeRect = newRect
        }
        
        dimm.suggestionFrameClosue = { [weak self] suggestion in
            return self?.frame(of: suggestion) ?? .zero
        }
        
        fillLayer = dimm
    }
    
    func configureBubleLayer(config: SuggestionsConfig) -> CALayer? {
        guard config.buble.shouldDraw else { return nil }
        var tempLayer: CALayer?
        let buble = BubleLayer(parent: layer, config: config, tempLayerClosure: { layer in
            tempLayer = layer
        })
        bubleLayer = buble
        
        return tempLayer
    }
    
    func configureTextLayer(superLayer: CALayer?, config: SuggestionsConfig) {
        let bubleLayer = superLayer ?? layer
        let textLayer = TextLayer(parent: bubleLayer, config: config)
        textLayer.suggestionFrameClosue = { [weak self] suggestion in
            return self?.frame(of: suggestion) ?? .zero
        }
        textLayer.textLayerUpdatedFrameClosue = { [weak self] newTextFrame in
            self?.textLayerRect = newTextFrame
        }
        
        self.textLayer = textLayer
    }
    
    func configureUnblurLayer(with blur: CALayer?, config: SuggestionsConfig) {
        guard let superBlur = blur else { return }
        unblurLayer = UnblurLayer(maskedLayer: superBlur, superBunds: bounds, config: config, filteredUsed: canUseFilteredLayer)
    }
    
    func configureBlurLayer(config: SuggestionsConfig) -> CALayer? {
        guard config.background.blurred else { return nil }
        var newLayer: CALayer?
        blurLayer = BlurLayer(parent: layer, config: config, filteredUsed: canUseFilteredLayer, tempLayerClosure: { layer in
            newLayer = layer
        })
        
        return newLayer
    }
    
    func configureSublayers(config: SuggestionsConfig) {
        let newLayer = configureBlurLayer(config: config)
        configureUnblurLayer(with: newLayer, config: config)
        configreDimmLayer(config: config)
        let temp = configureBubleLayer(config: config)
        configureTextLayer(superLayer: temp, config: config)
    }
    
    func configureMainView() {
        guard let superview = UIApplication.shared.keyWindow else { return }
        let main = MainView(parent: superview)
        main.alpha = 0.0
        main.mainViewResizedBlock = { [weak self] frame in
            self?.perfromWithDelayAndCanceling()
        }
        mainView = main
    }
    
    func configure(with config: SuggestionsConfig) {
        configureMainView()
        configureGestures()
        configureAppearance()
        configureSublayers(config: config)
    }
}
