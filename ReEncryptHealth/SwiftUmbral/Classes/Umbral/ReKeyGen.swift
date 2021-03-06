//
//  ReKeyGen.swift
//  SwiftUmbral
//
//  Created by Alex Vlasov on 10/10/2018.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import Foundation
import EllipticSwift
import CryptoSwift
import BigInt

public final class RekeyGenerator {
    enum Error: Swift.Error {
        case invalidThreshold
        case invalidDelegatorKey
        case noEntropy
    }
    
    public static func generateRekeyFragments<T, U>(parameters: T,
                                             delegatorKey: UmbralKey<T, U>,
                                             delegateeKey: UmbralKey<T, U>,
                                             numFragments: Int,
                                             threshold: Int) throws -> [KeyFragment<T, U>]? where T: UmbralParameters<U>, U: PrimeFieldProtocol {
        if numFragments < threshold {
            throw Error.invalidThreshold
        }
        guard let privateKey = delegatorKey.bnKey else {
            throw Error.invalidDelegatorKey
        }
        let keyLength = parameters.curveKeySizeBytes
        guard let randomXbytes = getRandomBytes(length: keyLength) else {
            throw Error.noEntropy
        }
        let field = parameters.curveOrderField
        let xa = PrimeFieldElement.fromBytes(randomXbytes, field: field)
        let Xa = (xa.nativeValue * parameters.G).toAffine()
        let ephemDHPoint = xa.nativeValue * delegateeKey.pubkey
        let dhInZq = try parameters.H3((Xa,
                                    delegateeKey.pubkey, ephemDHPoint.toAffine()))
        let d = PrimeFieldElement.fromValue(dhInZq, field: field)
        let a = PrimeFieldElement.fromValue(privateKey, field: field)
        let f0 = a * (d.inv())
//        print("f0")
//        print(String(BigUInt(f0.nativeValue.bytes), radix: 10))
        let DHPoint = a.nativeValue * delegateeKey.pubkey
        let D = try parameters.H3((delegatorKey.pubkey,
                                   delegateeKey.pubkey, DHPoint.toAffine()))
        if threshold == 1 && numFragments == 1 {
            guard let randomYbytes = getRandomBytes(length: keyLength) else {
                throw Error.noEntropy
            }
            guard let randomIDbytes = getRandomBytes(length: keyLength) else {
                throw Error.noEntropy
            }
            let y = PrimeFieldElement.fromBytes(randomYbytes, field: field)
            let id = PrimeFieldElement.fromBytes(randomIDbytes, field: field)
            let Y = (y.nativeValue * parameters.G).toAffine()
//            let skBytes = parameters.hashFunction(parameters.serializeZq(id.nativeValue)! + parameters.serializeZq(D)!)
//            let sk = PrimeFieldElement.fromBytes(skBytes, field: field)
            let rk = f0
            let U1 = (rk.nativeValue * parameters.U).toAffine()
            var toHash = Data()
            toHash.append(parameters.serializePoint(Y)!)
            toHash.append(parameters.serializeZq(id.nativeValue)!)
            toHash.append(parameters.serializePoint(delegatorKey.pubkey)!)
            toHash.append(parameters.serializePoint(delegateeKey.pubkey)!)
            toHash.append(parameters.serializePoint(U1)!)
            toHash.append(parameters.serializePoint(Xa)!)
            let h = parameters.hashFunction(toHash)
            let z1 = PrimeFieldElement.fromBytes(h, field: field)
            let z2 = y - a * z1
            var fragment = KeyFragment.init(params: parameters)
            fragment.id = id.nativeValue
            fragment.rk = rk.nativeValue
            fragment.Xa = Xa
            fragment.U1 = U1
            fragment.z1 = z1.nativeValue
            fragment.z2 = z2.nativeValue
            return [fragment]
        } else {
            var randomFE = [PrimeFieldElement<T.CurveOrderField>]()
            randomFE.reserveCapacity(threshold - 1)
            for _ in 0 ..< threshold - 1 {
//                let randomTbytes = Data(repeating: 0, count: keyLength)
                guard let randomTbytes = getRandomBytes(length: keyLength) else {
                    throw Error.noEntropy
                }
                let t = PrimeFieldElement.fromBytes(randomTbytes, field: field)
                randomFE.append(t)
            }
            let allCoeffs = [f0] + randomFE
            let poly = PrimeFieldPolynomial.init(allCoeffs)
//            print(poly.description)
            var fragments = [KeyFragment<T, U>]()
            fragments.reserveCapacity(numFragments)
            for _ in 0 ..< numFragments {
                guard let randomYbytes = getRandomBytes(length: keyLength) else {
                    throw Error.noEntropy
                }
                guard let randomIDbytes = getRandomBytes(length: keyLength) else {
                    throw Error.noEntropy
                }
                let y = PrimeFieldElement.fromBytes(randomYbytes, field: field)
                let id = PrimeFieldElement.fromBytes(randomIDbytes, field: field)
                let Y = (y.nativeValue * parameters.G).toAffine()
                let skBytes = parameters.hashFunction(parameters.serializeZq(id.nativeValue)! + parameters.serializeZq(D)!)
                let sk = PrimeFieldElement.fromBytes(skBytes, field: field)

                let rk = poly.evaluate(sk)
//                print("rk")
//                print(String(BigUInt(rk.nativeValue.bytes), radix: 10))
                let U1 = (rk.nativeValue * parameters.U).toAffine()
                var toHash = Data()
                toHash.append(parameters.serializePoint(Y)!)
                toHash.append(parameters.serializeZq(id.nativeValue)!)
                toHash.append(parameters.serializePoint(delegatorKey.pubkey)!)
                toHash.append(parameters.serializePoint(delegateeKey.pubkey)!)
                toHash.append(parameters.serializePoint(U1)!)
                toHash.append(parameters.serializePoint(Xa)!)
                let h = parameters.hashFunction(toHash)
                let z1 = PrimeFieldElement.fromBytes(h, field: field)
                let z2 = y - a * z1
                var fragment = KeyFragment.init(params: parameters)
                fragment.id = id.nativeValue
                fragment.rk = rk.nativeValue
                fragment.Xa = Xa
                fragment.U1 = U1
                fragment.z1 = z1.nativeValue
                fragment.z2 = z2.nativeValue
                fragments.append(fragment)
            }
            return fragments
        }
    }

}
