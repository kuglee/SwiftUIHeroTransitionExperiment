// from: https://shadowfacts.net/2023/swiftui-hero-transition

import SwiftUI

struct ContentView: View {
  @State var presented: Bool = false

  var body: some View {
    VStack {
      Image("pranked").resizable().scaledToFit().frame(width: 100)
        .matchedGeometrySource(id: "image")
      Button {
        presented.toggle()
      } label: {
        Text("Present")
      }
    }
    .matchedGeometryPresentation(isPresented: $presented) {
      VStack { Image("pranked").resizable().scaledToFit().matchedGeometryDestination(id: "image") }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { Button("Close") { presented = false }.padding() }
    }
  }
}

struct MatchedContainerView: View {
  let sources: [(id: AnyHashable, view: AnyView, frame: CGRect)]
  @ObservedObject var state: MatchedGeometryState

  var body: some View {
    ZStack { ForEach(sources, id: \.id) { (id, view, _) in matchedView(id: id, source: view) } }
  }

  func matchedView(id: AnyHashable, source: AnyView) -> some View {
    let frame = state.currentFrames[id]!
    let dest = state.destinations[id]!.0
    let sourceOpacity: Double = if state.animating { 0 } else { 1 }
    return ZStack {
      source.opacity(sourceOpacity)
      dest
    }
    .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
    .ignoresSafeArea()
    .animation(
      .interpolatingSpring(mass: 1, stiffness: 150, damping: 15, initialVelocity: 0),
      value: frame
    )
  }
}

#Preview { ContentView() }

struct ViewControllerPresenter: UIViewControllerRepresentable {
  let makeVC: () -> UIViewController
  @Binding var isPresented: Bool

  func makeUIViewController(context: Context) -> UIViewController { return UIViewController() }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    if isPresented {
      if uiViewController.presentedViewController == nil {
        let presented = makeVC()
        presented.presentationController!.delegate = context.coordinator
        uiViewController.present(presented, animated: true)
        context.coordinator.didPresent = true
      }
    } else {
      if context.coordinator.didPresent,
        let presentedViewController = uiViewController.presentedViewController,
        !presentedViewController.isBeingDismissed
      {
        uiViewController.dismiss(animated: true)
      }
    }
  }

  func makeCoordinator() -> Coordinator { return Coordinator(isPresented: $isPresented) }

  class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    @Binding var isPresented: Bool
    var didPresent = false

    init(isPresented: Binding<Bool>) { self._isPresented = isPresented }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
      isPresented = false
      didPresent = false
    }
  }
}

struct MatchedGeometrySourcesKey: PreferenceKey {
  static let defaultValue: [AnyHashable: (AnyView, CGRect)] = [:]
  static func reduce(value: inout Value, nextValue: () -> Value) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

struct MatchedGeometrySourceModifier<Matched: View>: ViewModifier {
  let id: AnyHashable
  let matched: Matched
  @EnvironmentObject private var state: MatchedGeometryState

  func body(content: Content) -> some View {
    content.background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: MatchedGeometrySourcesKey.self,
          value: [id: (AnyView(matched), proxy.frame(in: .global))]
        )
      }
    )
    .opacity(state.animating ? 0 : 1)
  }
}

struct PresentViewControllerModifier: ViewModifier {
  let makeVC: () -> UIViewController
  @Binding var isPresented: Bool

  func body(content: Content) -> some View {
    ViewControllerPresenter(makeVC: makeVC, isPresented: $isPresented)
  }
}

extension View {
  func matchedGeometrySource<ID: Hashable>(id: ID) -> some View {
    self.modifier(MatchedGeometrySourceModifier(id: AnyHashable(id), matched: self))
  }
}

extension View {
  func presentViewController(_ makeVC: @escaping () -> UIViewController, isPresented: Binding<Bool>)
    -> some View
  { self.modifier(PresentViewControllerModifier(makeVC: makeVC, isPresented: isPresented)) }
}

extension View {
  func matchedGeometryPresentation<Presented: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder presenting: () -> Presented
  ) -> some View {
    self.modifier(
      MatchedGeometryPresentationModifier(isPresented: isPresented, presented: presenting())
    )
  }
}

struct MatchedGeometryPresentationModifier<Presented: View>: ViewModifier {
  @Binding var isPresented: Bool
  let presented: Presented
  @StateObject private var state = MatchedGeometryState()

  func body(content: Content) -> some View {
    content.environmentObject(state)
      .backgroundPreferenceValue(MatchedGeometrySourcesKey.self) { sources in
        Color.clear.presentViewController(makeVC(sources: sources), isPresented: $isPresented)
      }
  }

  private func makeVC(sources: [AnyHashable: (AnyView, CGRect)]) -> () -> UIViewController {
    return {
      return MatchedGeometryViewController(sources: sources, content: presented, state: state)
    }
  }
}

class MatchedGeometryViewController<Content: View>: UIViewController,
  UIViewControllerTransitioningDelegate
{
  let sources: [AnyHashable: (AnyView, CGRect)]
  let content: Content
  let state: MatchedGeometryState
  var contentHost: UIHostingController<ContentContainerView<Content>>!
  var matchedHost: UIHostingController<MatchedContainerView>!

  init(sources: [AnyHashable: (AnyView, CGRect)], content: Content, state: MatchedGeometryState) {
    self.sources = sources
    self.content = content
    self.state = state

    super.init(nibName: nil, bundle: nil)

    modalPresentationStyle = .custom
    transitioningDelegate = self
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.addMatchedHostingController()
    self.addContentContrller()
  }

  func addMatchedHostingController() {
    let sources = self.sources.map { (id: $0.key, view: $0.value.0, frame: $0.value.1) }
    let matchedContainer = MatchedContainerView(sources: sources, state: state)
    matchedHost = UIHostingController(rootView: matchedContainer)
    matchedHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    matchedHost.view.frame = view.bounds
    matchedHost.view.backgroundColor = .clear
    matchedHost.view.layer.zPosition = 100
    addChild(matchedHost)
    view.addSubview(matchedHost.view)
    matchedHost.didMove(toParent: self)
  }

  func addContentContrller() {
    let contentContainer = ContentContainerView(content: content, state: state)
    contentHost = UIHostingController(rootView: contentContainer)
    contentHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    contentHost.view.frame = view.bounds
    addChild(contentHost)
    view.addSubview(contentHost.view)
    contentHost.didMove(toParent: self)
  }

  func animationController(
    forPresented presented: UIViewController,
    presenting: UIViewController,
    source: UIViewController
  ) -> (any UIViewControllerAnimatedTransitioning)? {
    MatchedGeometryPresentationAnimationController<Content>()
  }

  func animationController(forDismissed dismissed: UIViewController) -> (
    any UIViewControllerAnimatedTransitioning
  )? { MatchedGeometryDismissAnimationController<Content>() }

  func presentationController(
    forPresented presented: UIViewController,
    presenting: UIViewController?,
    source: UIViewController
  ) -> UIPresentationController? {
    return MatchedGeometryPresentationController(
      presentedViewController: presented,
      presenting: presenting
    )
  }
}

class MatchedGeometryPresentationController: UIPresentationController {
  override func dismissalTransitionWillBegin() {
    super.dismissalTransitionWillBegin()
    delegate?.presentationControllerWillDismiss?(self)
  }
}

struct MatchedGeometryDestinationModifier<Matched: View>: ViewModifier {
  let id: AnyHashable
  let matched: Matched
  @EnvironmentObject private var state: MatchedGeometryState

  func body(content: Content) -> some View {
    content.background(
      GeometryReader { proxy in
        Color.clear
          .preference(key: MatchedGeometryDestinationFrameKey.self, value: proxy.frame(in: .global))
          .onPreferenceChange(MatchedGeometryDestinationFrameKey.self) { newValue in
            if let newValue { state.destinations[id] = (AnyView(matched), newValue) }
          }
      }
    )
    .opacity(state.animating ? 0 : 1)
  }
}

extension View {
  func matchedGeometryDestination<ID: Hashable>(id: ID) -> some View {
    self.modifier(MatchedGeometryDestinationModifier(id: AnyHashable(id), matched: self))
  }
}

struct MatchedGeometryDestinationFrameKey: PreferenceKey {
  static let defaultValue: CGRect? = nil
  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() }
}

class MatchedGeometryState: ObservableObject {
  @Published var destinations: [AnyHashable: (AnyView, CGRect)] = [:]
  @Published var animating: Bool = false
  @Published var currentFrames: [AnyHashable: CGRect] = [:]
  @Published var mode: Mode = .presenting

  enum Mode { case presenting, dismissing }
}

struct ContentContainerView<Content: View>: View {
  let content: Content
  let state: MatchedGeometryState

  var body: some View { content.environmentObject(state) }
}

class MatchedGeometryPresentationAnimationController<Content: View>: NSObject,
  UIViewControllerAnimatedTransitioning
{
  func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?)
    -> TimeInterval
  { return 1 }

  func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
    let matchedGeomVC =
      transitionContext.viewController(forKey: .to) as! MatchedGeometryViewController<Content>
    matchedGeomVC.state.animating = false
    let container = transitionContext.containerView

    container.addSubview(matchedGeomVC.view)

    let cancellable = matchedGeomVC.state.$destinations
      .filter { destinations in
        matchedGeomVC.sources.allSatisfy { source in destinations.keys.contains(source.key) }
      }
      .first()
      .sink { _ in
        matchedGeomVC.addMatchedHostingController()

        matchedGeomVC.state.mode = .presenting
        matchedGeomVC.state.currentFrames = matchedGeomVC.sources.mapValues(\.1)

        DispatchQueue.main.async {
          matchedGeomVC.state.animating = true
          matchedGeomVC.state.currentFrames = matchedGeomVC.state.destinations.mapValues(\.1)
        }
      }

    matchedGeomVC.contentHost.view.layer.opacity = 0
    let spring = UISpringTimingParameters(
      mass: 1,
      stiffness: 150,
      damping: 15,
      initialVelocity: .zero
    )
    let animator = UIViewPropertyAnimator(
      duration: self.transitionDuration(using: transitionContext),
      timingParameters: spring
    )
    animator.addAnimations { matchedGeomVC.contentHost.view.layer.opacity = 1 }
    animator.addCompletion { _ in
      transitionContext.completeTransition(true)
      matchedGeomVC.state.animating = false

      cancellable.cancel()
      matchedGeomVC.matchedHost?.view.isHidden = true
    }
    animator.startAnimation()
  }
}

class MatchedGeometryDismissAnimationController<Content: View>: NSObject,
  UIViewControllerAnimatedTransitioning
{
  func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?)
    -> TimeInterval
  { return 1 }

  func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
    let matchedGeomVC =
      transitionContext.viewController(forKey: .from) as! MatchedGeometryViewController<Content>
    matchedGeomVC.state.animating = false
    let container = transitionContext.containerView

    container.addSubview(matchedGeomVC.view)

    matchedGeomVC.state.mode = .dismissing
    matchedGeomVC.state.currentFrames = matchedGeomVC.state.destinations.mapValues(\.1)

    DispatchQueue.main.async {
      matchedGeomVC.state.animating = true
      matchedGeomVC.state.currentFrames = matchedGeomVC.sources.mapValues(\.1)
    }

    matchedGeomVC.contentHost.view.layer.opacity = 0
    let spring = UISpringTimingParameters(
      mass: 1,
      stiffness: 150,
      damping: 15,
      initialVelocity: .zero
    )
    let animator = UIViewPropertyAnimator(
      duration: self.transitionDuration(using: transitionContext),
      timingParameters: spring
    )
    animator.addAnimations { matchedGeomVC.contentHost.view.layer.opacity = 1 }
    animator.addCompletion { _ in
      transitionContext.completeTransition(true)
      matchedGeomVC.state.animating = false

      matchedGeomVC.matchedHost.view.isHidden = true
    }
    animator.startAnimation()
  }
}
