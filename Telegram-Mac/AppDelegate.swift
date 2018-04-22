import Cocoa

import SwiftSignalKitMac
import PostboxMac
import TelegramCoreMac
import TGUIKit
import Quartz
import MtProtoKitMac
import CoreServices
import LocalAuthentication

#if !APP_STORE
    import HockeySDK
    import Sparkle
#endif




@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, NSWindowDelegate {
   
    #if !APP_STORE
    @IBOutlet weak var updater: SUUpdater!
    #endif
    @IBOutlet weak var window: Window! {
        didSet {
            window.delegate = self
            window.initSaver()
        }
    }
    
    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_: with:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    
    /*
     {
     set {
     
     }
     get {
     // let path = "\(Bundle.main.bundlePath)/Contents/Frameworks/Sparkle.framework"
     // return SUUpdater.init(for: Bundle.init(identifier: ""))
     }
     }
 */

    
    let presentAccountStatus = Promise(false)
    fileprivate let nofityDisposable:MetaDisposable = MetaDisposable()
    var containerUrl:String!
    
    private let accountManagerPromise = Promise<AccountManager>()
    private var contextValue: ApplicationContext?
    private let context = Promise<ApplicationContext?>()
    private let contextDisposable = MetaDisposable()
    private let handleEventContextDisposable = MetaDisposable()
    private var activity:Any?


    func applicationWillFinishLaunching(_ notification: Notification) {
       
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        
        let appGroupName = "6N38VWS5BX.ru.keepcoder.Telegram"
        guard let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) else {
            return
        }
        
        uiLocalizationFunc = { key in
            return _NSLocalizedString(key)
        }
        
        DateUtils.setDateLocalizationFunc ({ key -> String in
            return _NSLocalizedString(key)
        })
        
        
       // applyMainMenuLocalization(window)
        
        mw = window
        self.containerUrl = containerUrl.path
        
        #if !APP_STORE
            self.updater.automaticallyChecksForUpdates = true
           // self.updater.automaticallyDownloadsUpdates = false
            self.updater.checkForUpdatesInBackground()
        #endif
        
        
        Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(checkUpdates), userInfo: nil, repeats: true)
        
        
        
        for argument in CommandLine.arguments {
            switch argument {
            case "DEBUG_SESSION":
                isDebug = true
            default:
                break
            }
        }
        
        if !isDebug {
            #if BETA

                let hockeyAppId:String = "6ed2ac3049e1407387c2f1ffcb74e81f"
                BITHockeyManager.shared().configure(withIdentifier: hockeyAppId)
                BITHockeyManager.shared().crashManager.isAutoSubmitCrashReport = true
                BITHockeyManager.shared().start()

            #endif
//            
//            #if STABLE     
//                let hockeyAppId:String = "d77af558b21e0878953100680b5ac66a"
//                BITHockeyManager.shared().configure(withIdentifier: hockeyAppId)
//                BITHockeyManager.shared().crashManager.isAutoSubmitCrashReport = false
//            #endif
            
        }
        

        telegramUIDeclareEncodables()
        
        MTLogSetEnabled(UserDefaults.standard.bool(forKey: "enablelogs"))

        let logger = Logger(basePath: containerUrl.path + "/logs")
        logger.logToConsole = false
        logger.logToFile = UserDefaults.standard.bool(forKey: "enablelogs")
        
        #if DEBUG
            MTLogSetEnabled(true)
            logger.logToFile = true
        #endif
        
//        #if APP_STORE || STABLE
//            logger.logToConsole = false
//            MTLogSetEnabled(false)
//        #endif
        
        Logger.setSharedLogger(logger)
        
        #if !APP_STORE
            if let feedUrl = Bundle.main.infoDictionary?["SUFeedURL"] as? String, let url = URL(string: feedUrl) {
                updater.feedURL = url
            }
        #endif
        
        
       
        let bundleId = Bundle.main.bundleIdentifier
        if let bundleId = bundleId {
            LSSetDefaultHandlerForURLScheme("tg" as CFString, bundleId as CFString)
        }
   
        
        
        self.accountManagerPromise.set(accountManager(basePath: containerUrl.path + "/accounts-metadata"))

        let _ = (accountManagerPromise.get()
            |> mapToSignal { manager in
                return managedCleanupAccounts(networkArguments: NetworkInitializationArguments(apiId: API_ID, languagesCategory: languagesCategory), accountManager: manager, appGroupPath: containerUrl.path, auxiliaryMethods: telegramAccountAuxiliaryMethods)
            }).start()
        
        
        
        
        self.context.set(self.accountManagerPromise.get() |> deliverOnMainQueue |> mapToSignal { accountManager -> Signal<ApplicationContext?, NoError> in
            return applicationContext(window: self.window, shouldOnlineKeeper: self.presentAccountStatus.get(), accountManager: accountManager, appGroupPath: containerUrl.path, testingEnvironment: TEST_SERVER)
        })
        

        self.contextDisposable.set(self.context.get().start(next: { context in
            assert(Queue.mainQueue().isCurrent())
            self.window.makeKeyAndOrderFront(self)
            self.contextValue = context
            self.window.contentView?.removeAllSubviews()
            
            context?.showRoot(for: self.window)
            
        }))
        
        print("Hello, Ash Furrow")
        
        self.window.contentView?.wantsLayer = true

    }
    
    @objc func checkUpdates() {
        #if !APP_STORE
            updater.checkForUpdatesInBackground()
        #endif
    }
    
    private static var eventProcessed: Bool = false
    
    @objc func handleURLEvent(_ event:NSAppleEventDescriptor, with replyEvent:NSAppleEventDescriptor) {
        AppDelegate.eventProcessed = false
        let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue
        self.handleEventContextDisposable.set((self.context.get()).start(next: {  context in
            if !AppDelegate.eventProcessed {
                NSApp.activate(ignoringOtherApps: true)
                self.window.deminiaturize(self)
                
                if let url = url, let context = context  {
                    switch context {
                    case let .authorized(context):
                        AppDelegate.eventProcessed = true
                        let link = inApp(for: url as NSString, account: context.account, openInfo: { (peerId, isChat, postId, action) in
                            context.rightController.push(ChatController(account: context.account, peerId: peerId, messageId:postId, initialAction:action), true)
                        }, applyProxy: { proxy in
                            applyExternalProxy(proxy, postbox: context.account.postbox, network: context.account.network)
                        })
                        
                        execute(inapp: link)
                    case .unauthorized(let context):
                        let settings = proxySettings(from: url)
                        if settings.1 {
                            AppDelegate.eventProcessed = true
                            if let proxy = settings.0 {
                                applyExternalProxy(proxy, postbox: context.account.postbox, network: context.account.network)
                            } else {
                                _ = applyProxySettings(postbox: context.account.postbox, network: context.account.network, settings: nil).start()
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }))
    }
    
    
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        var rect = rect
        rect.origin.y -= 22
        return rect;
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        presentAccountStatus.set(.single(true) |> then(.single(true) |> delay(50, queue: Queue.concurrentBackgroundQueue())) |> restart)
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        presentAccountStatus.set(.single(false))
    }
    
    func applicationDidHide(_ notification: Notification) {
        presentAccountStatus.set(.single(false))
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(sender)
        
        return true
    }
    
    
    override func acceptsPreviewPanelControl(_ panel:QLPreviewPanel) ->Bool {
        return true
    }
    
    
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.delegate = QuickLookPreview.current
        panel.dataSource = QuickLookPreview.current
    }
    
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.delegate = nil
        panel.dataSource = nil
        QuickLookPreview.current.hide()
    }
    
   

   
    @IBAction func paste(_ sender: Any) {
        if let window = NSApp.keyWindow as? Window {
            window.pasteToFirstResponder(sender)
        }
    }
    @IBAction func copy(_ sender: Any) {
        if let window = NSApp.keyWindow as? Window {
            window.copyFromFirstResponder(sender)
        }
    }
    
    func applicationWillUnhide(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        if contextValue != nil {
            window.makeKeyAndOrderFront(nil)
        }
    }

    override func awakeFromNib() {
        #if APP_STORE
            if let menu = NSApp.mainMenu?.item(at: 0)?.submenu, let sparkleItem = menu.item(withTag: 1000) {
                menu.removeItem(sparkleItem)
            }
        #endif
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        #if !APP_STORE
            updater.checkForUpdates(sender)
        #endif
    }
    
    
    @IBAction func unhide(_ sender: Any) {
         window.makeKeyAndOrderFront(sender)
    }
    //  LocalizationWrapper.setLanguageCode("ru")
    
    @IBAction func aboutAction(_ sender: Any) {
        window.makeKeyAndOrderFront(sender)
        showModal(with: AboutModalController(), for: window)
    }
    @IBAction func preferencesAction(_ sender: Any) {
        window.makeKeyAndOrderFront(sender)
        if let context = self.contextValue {
            switch context {
            case let .authorized(appContext):
                appContext.leftController.showPreferences()
                if !(appContext.rightController.controller is GeneralSettingsViewController) {
                    appContext.rightController.push(GeneralSettingsViewController(appContext.account), false)
                }
            default:
                break
            }
        }
    }
    @IBAction func closeWindow(_ sender: Any) {
        NSApp.keyWindow?.close()
    }
    
    @IBAction func showQuickSwitcher(_ sender: Any) {
        window.makeKeyAndOrderFront(sender)
        if let context = contextValue {
            switch context {
            case .authorized(let authorized):
                if !authorized.isLocked {
                    showModal(with: QuickSwitcherModalController(account: authorized.account), for: mainWindow)
                }
            default:
                break
            }
        }
    }
}
