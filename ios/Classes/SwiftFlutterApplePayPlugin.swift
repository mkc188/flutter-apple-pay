import Flutter
import UIKit
import Foundation
import PassKit
// import Stripe

typealias AuthorizationCompletion = (_ payment: PKPayment) -> Void
typealias AuthorizationViewControllerDidFinish = (_ error : NSDictionary) -> Void
typealias CompletionHandler = (PKPaymentAuthorizationStatus) -> Void

public class SwiftFlutterApplePayPlugin: NSObject, FlutterPlugin, PKPaymentAuthorizationViewControllerDelegate {
    var authorizationCompletion : AuthorizationCompletion!
    var authorizationViewControllerDidFinish : AuthorizationViewControllerDidFinish!
    var pkrequest = PKPaymentRequest()
    var flutterResult: FlutterResult!;
    var completionHandler: CompletionHandler!
    
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_apple_pay", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SwiftFlutterApplePayPlugin(), channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getStripeToken" {
            flutterResult = result;
            let parameters = NSMutableDictionary()
            var payments: [PKPaymentNetwork] = []
            var items = [PKPaymentSummaryItem]()
            var totalPrice:Double = 0.0
            let arguments = call.arguments as! NSDictionary
            
            guard let paymentNeworks = arguments["paymentNetworks"] as? [String] else {return}
            guard let countryCode = arguments["countryCode"] as? String else {return}
            guard let currencyCode = arguments["currencyCode"] as? String else {return}

//            guard let stripePublishedKey = arguments["stripePublishedKey"] as? String else {return}
            guard let paymentItems = arguments["paymentItems"] as? [NSDictionary] else {return}
            guard let merchantIdentifier = arguments["merchantIdentifier"] as? String else {return}
            
            for dictionary in paymentItems {
                guard let label = dictionary["label"] as? String else {return}
                guard let price = dictionary["amount"] as? Double else {return}
                let type = PKPaymentSummaryItemType.final
                
                totalPrice += price
                
                // items.append(PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(floatLiteral: price), type: type))
                items.append(PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(floatLiteral: price)))
            }
            
            // Stripe.setDefaultPublishableKey(stripePublishedKey)
            
            // let total = PKPaymentSummaryItem(label: "Total", amount: NSDecimalNumber(floatLiteral:totalPrice), type: .final)
            // items.append(total)
            
            paymentNeworks.forEach {
                
                guard let paymentType = PaymentSystem(rawValue: $0) else {
                    assertionFailure("No payment type found")
                    return
                }
                
                payments.append(paymentType.paymentNetwork)
            }
            
            parameters["paymentNetworks"] = payments
            // parameters["requiredShippingContactFields"] = [PKContactField.name, PKContactField.postalAddress] as Set
            parameters["merchantCapabilities"] = PKMerchantCapability.capability3DS // optional
            
            parameters["merchantIdentifier"] = merchantIdentifier
            parameters["countryCode"] = countryCode
            parameters["currencyCode"] = currencyCode
            
            parameters["paymentSummaryItems"] = items
            
            makePaymentRequest(parameters: parameters,  authCompletion: authorizationCompletion, authControllerCompletion: authorizationViewControllerDidFinish)
        }
        else if call.method == "closeApplePaySheetWithSuccess" {
            closeApplePaySheetWithSuccess()
        }
        else if call.method == "closeApplePaySheetWithError" {
            closeApplePaySheetWithError()
        }
        else if call.method == "canMakePayments" {
            result(PKPaymentAuthorizationViewController.canMakePayments())
        }
        else {
            result("Flutter method not implemented on iOS")
        }
    }
    
    func authorizationCompletion(_ payment: PKPayment) {
        // success
        var result: [String: Any] = [:]
        result["pk_token"] = String(data: payment.token.paymentData, encoding: String.Encoding.utf8)
        result["pk_token_instrument_name"] = payment.token.paymentMethod.displayName
        result["pk_token_payment_network"] = payment.token.paymentMethod.network
        result["pk_token_transaction_id"] = payment.token.transactionIdentifier

        flutterResult(result)
    }
    
    func authorizationViewControllerDidFinish(_ error : NSDictionary) {
        //error
        flutterResult(error)
    }
    
    enum PaymentSystem: String {
        case visa
        case mastercard
        case amex
        // case quicPay
        // case chinaUnionPay
        // case discover
        // case interac
        // case privateLabel
        
        var paymentNetwork: PKPaymentNetwork {
            
            switch self {
                case .mastercard: return PKPaymentNetwork.masterCard
                case .visa: return PKPaymentNetwork.visa
                case .amex: return PKPaymentNetwork.amex
                // case .quicPay: return PKPaymentNetwork.quicPay
                // case .chinaUnionPay: return PKPaymentNetwork.chinaUnionPay
                // case .discover: return PKPaymentNetwork.discover
                // case .interac: return PKPaymentNetwork.interac
                // case .privateLabel: return PKPaymentNetwork.privateLabel
            }
        }
    }
    
    func makePaymentRequest(parameters: NSDictionary, authCompletion: @escaping AuthorizationCompletion, authControllerCompletion: @escaping AuthorizationViewControllerDidFinish) {
        guard let paymentNetworks               = parameters["paymentNetworks"]                 as? [PKPaymentNetwork] else {return}
        // guard let requiredShippingContactFields = parameters["requiredShippingContactFields"]   as? Set<PKContactField> else {return}
        let merchantCapabilities : PKMerchantCapability = parameters["merchantCapabilities"]    as? PKMerchantCapability ?? .capability3DS
        
        guard let merchantIdentifier            = parameters["merchantIdentifier"]              as? String else {return}
        guard let countryCode                   = parameters["countryCode"]                     as? String else {return}
        guard let currencyCode                  = parameters["currencyCode"]                    as? String else {return}
        
        guard let paymentSummaryItems           = parameters["paymentSummaryItems"]             as? [PKPaymentSummaryItem] else {return}
        
        authorizationCompletion = authCompletion
        authorizationViewControllerDidFinish = authControllerCompletion
        
        // Cards that should be accepted
        if PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: paymentNetworks) {
            
            pkrequest.merchantIdentifier = merchantIdentifier
            pkrequest.countryCode = countryCode
            pkrequest.currencyCode = currencyCode
            pkrequest.supportedNetworks = paymentNetworks
            // pkrequest.requiredShippingContactFields = requiredShippingContactFields
            // This is based on using Stripe
            pkrequest.merchantCapabilities = merchantCapabilities
            
            pkrequest.paymentSummaryItems = paymentSummaryItems
            
            let authorizationViewController = PKPaymentAuthorizationViewController(paymentRequest: pkrequest)
            
            if let viewController = authorizationViewController {
                viewController.delegate = self
                guard let currentViewController = UIApplication.shared.keyWindow?.topMostViewController() else {
                    return
                }
                currentViewController.present(viewController, animated: true)
            }
        } else {
            let error: NSDictionary = ["message": "User not added some cards", "code": "404"]
            authControllerCompletion(error)
         }

        return
    }
    
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, completion: @escaping (PKPaymentAuthorizationStatus) -> Void) {
        
//        STPAPIClient.shared().createToken(with: payment) { (stripeToken, error) in
//            guard error == nil, let stripeToken = stripeToken else {
//                print(error!)
//                completion(PKPaymentAuthorizationStatus.failure)
//                return
//            }
//
//            self.authorizationCompletion(stripeToken.stripeID)
//            self.completionHandler = completion
//        }
        
        self.authorizationCompletion(payment)
        self.completionHandler = completion
        

    }

    public func closeApplePaySheetWithSuccess() {
        if (self.completionHandler != nil) {
            self.completionHandler(PKPaymentAuthorizationStatus.success)
        }
    }

    public func closeApplePaySheetWithError() {
        if (self.completionHandler != nil) {
            self.completionHandler(PKPaymentAuthorizationStatus.failure)
        }
    }
    
    public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        // Dismiss the Apple Pay UI
        guard let currentViewController = UIApplication.shared.keyWindow?.topMostViewController() else {
            return
        }
        currentViewController.dismiss(animated: true, completion: nil)
        // let error: NSDictionary = ["message": "User closed apple pay", "code": "400"]
        // authorizationViewControllerDidFinish(error)
    }
    
    func makePaymentSummaryItems(itemsParameters: Array<Dictionary <String, Any>>) -> [PKPaymentSummaryItem]? {
        var items = [PKPaymentSummaryItem]()
        var totalPrice:Decimal = 0.0
        
        for dictionary in itemsParameters {
            
            guard let label = dictionary["label"] as? String else {return nil}
            guard let amount = dictionary["amount"] as? NSDecimalNumber else {return nil}
            guard let type = dictionary["type"] as? PKPaymentSummaryItemType else {return nil}
            
            totalPrice += amount.decimalValue
            
            items.append(PKPaymentSummaryItem(label: label, amount: amount, type: type))
        }
        
        let total = PKPaymentSummaryItem(label: "Total", amount: NSDecimalNumber(decimal:totalPrice), type: .final)
        items.append(total)
        print(items)
        return items
    }
    
}

extension UIWindow {
    func topMostViewController() -> UIViewController? {
        guard let rootViewController = self.rootViewController else {
            return nil
        }
        return topViewController(for: rootViewController)
    }
    
    func topViewController(for rootViewController: UIViewController?) -> UIViewController? {
        guard let rootViewController = rootViewController else {
            return nil
        }
        guard let presentedViewController = rootViewController.presentedViewController else {
            return rootViewController
        }
        switch presentedViewController {
        case is UINavigationController:
            let navigationController = presentedViewController as! UINavigationController
            return topViewController(for: navigationController.viewControllers.last)
        case is UITabBarController:
            let tabBarController = presentedViewController as! UITabBarController
            return topViewController(for: tabBarController.selectedViewController)
        default:
            return topViewController(for: presentedViewController)
        }
    }
}
