//
//  OperationStack.swift
//  Kingfisher
//
//  Created by Oleksiy Radyvanyuk on 30/05/2017.
//  Copyright © 2017 Wei Wang. All rights reserved.
//

import Foundation

class OperationStack: OperationQueue {
    func pushOperation(_ op: Operation) {
        setDependencies(for: op)
        addOperation(op)
    }

    func pushBlock(_ block: @escaping () -> Void) {
        pushOperation(BlockOperation(block: block))
    }

    let dependenciesLock: NSLock = {
        let result = NSLock()
        result.name = "nl.ngti.OperationStack.dependenciesLock"
        return result
    }()

    fileprivate func setDependencies(for operation: Operation) {
        dependenciesLock.lock()

        // suspend queue first
        let wasSuspended = isSuspended
        isSuspended = true

        // make the given operation a dependency for the last queued operation
        if let lastQueuedOperation = operations.last,
            !lastQueuedOperation.isExecuting {
            // ignore the operation that is being executed as setting
            // the dependency will have no effect on it
            lastQueuedOperation.addDependency(operation)
        }

        // resume suspended queue (if it was suspended before)
        isSuspended = wasSuspended

        dependenciesLock.unlock()
    }
}
