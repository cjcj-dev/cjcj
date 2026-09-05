class RefToken {}

struct RefAggregate {
    var token: RefToken

    init(token: RefToken) {
        this.token = token
    }

    func getToken(): RefToken {
        return token
    }
}

class RefHolder {
    var payload: RefAggregate

    init(payload: RefAggregate) {
        this.payload = payload
    }

    func read(): RefToken {
        return payload.getToken()
    }
}

func exerciseBaselessAS1Guard(holder: RefHolder): RefToken {
    return holder.read()
}
