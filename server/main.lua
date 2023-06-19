local spawnedPeds, netIdTable = {}, {}

-- get keys utils
local function get_key(t)
    local key
    for k, _ in pairs(t) do
        key = k
    end
    return key
end

-- Resource starting
AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    if Config.EnablePeds then BANK.CreatePeds() end
    local twoMonthMs = (os.time() - 5259487) * 1000
    MySQL.Sync.fetchScalar('DELETE FROM banking WHERE time < ? ', {twoMonthMs})
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    if Config.EnablePeds then BANK.DeletePeds() end
end)


AddEventHandler('esx:playerLoaded', function(playerId)
    if Config.EnablePeds then TriggerClientEvent('esx_banking:pedHandler', playerId, netIdTable) end
    local InvestedAmount = 0
    local xPlayer =ESX.GetPlayerFromId(playerId)
    if xPlayer.getAccount('invested') then
        InvestedAmount = xPlayer.getAccount('invested').money
        xPlayer.addAccountMoney('invested', ESX.Math.Round(InvestedAmount / Config.InvestmentFraction))
    end
end)


-- event
RegisterServerEvent('esx_banking:doingType')
AddEventHandler('esx_banking:doingType', function(typeData)
    if source == nil then return end
    if (typeData == nil) then return end

    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.getIdentifier()
    local money = xPlayer.getAccount('money').money
    local bankMoney = xPlayer.getAccount('bank').money

    local invested = 0
    if xPlayer.getAccount('invested') then
        invested = xPlayer.getAccount('invested').money
    end

    local amount

    local key = get_key(typeData)
    if typeData.deposit then
        amount = tonumber(typeData.deposit)
    elseif typeData.withdraw then
        amount = tonumber(typeData.withdraw)
    elseif typeData.invest then
        amount = tonumber(typeData.invest)
    elseif typeData.retrieve then
        amount = tonumber(typeData.retrieve)
    elseif typeData.transfer and typeData.transfer.moneyAmount then
        amount = tonumber(typeData.transfer.moneyAmount)
    elseif typeData.pincode then
        amount = tonumber(typeData.pincode)
    end

    if not tonumber(amount) then return end
    amount = ESX.Math.Round(amount)

    if amount == nil or (not typeData.pincode and amount <= 0) then
        TriggerClientEvent("esx:showNotification", source, TranslateCap('invalid_amount'), "error")
    else
        if typeData.deposit then
            -- deposit
            if amount <= money then
                BANK.Deposit(amount, xPlayer)
            else
                TriggerClientEvent("esx:showNotification", source, TranslateCap('not_enough_money', amount), "error")
                return
            end
        elseif typeData.invest then
            -- invest
            if bankMoney ~= nil and amount <= bankMoney then
                BANK.Invest(amount, xPlayer)
            else
                TriggerClientEvent("esx:showNotification", source, TranslateCap('not_enough_money', amount), "error")
                return
            end
        elseif typeData.retrieve then
            -- retrieve
            if  invested ~= nil and amount <= invested then
                BANK.Retrieve(amount, xPlayer)
            else
                TriggerClientEvent("esx:showNotification", source, TranslateCap('not_enough_money', amount), "error")
                return
            end
        elseif typeData.withdraw then
            -- withdraw
            if bankMoney ~= nil and amount <= bankMoney then
                BANK.Withdraw(amount, xPlayer)
            else
                TriggerClientEvent("esx:showNotification", source, TranslateCap('not_enough_money', amount), "error")
                return
            end
        elseif typeData.pincode then
            -- pincode
            BANK.Pincode(amount, identifier)
        elseif typeData.transfer then
            -- transfer
            if tonumber(typeData.transfer.playerId) <= 0 then
                TriggerClientEvent("esx:showNotification", source, TranslateCap("cant_do_it"), "error")
                return
            end

            if bankMoney < amount then
                TriggerClientEvent("esx:showNotification", source, TranslateCap('not_enough_money', amount), "error")
                return
            end

            local xTarget = ESX.GetPlayerFromId(tonumber(typeData.transfer.playerId))
            if not BANK.Transfer(xTarget, xPlayer, amount, key) then
                return
            end
        else
            TriggerClientEvent("esx:showNotification", source, TranslateCap('invalid_operation'), "error")
            return
        end

        money = xPlayer.getAccount('money').money
        bankMoney = xPlayer.getAccount('bank').money
        if typeData.transfer then
            TriggerClientEvent("esx:showNotification", source,
                TranslateCap(string.format('%s_money', key), amount, typeData.transfer.playerId), "success")
        else
            TriggerClientEvent("esx:showNotification", source, TranslateCap(string.format('%s_money', key), typeData.pincode and (string.format("%04d", amount)) or amount), "success")
        end
        if not typeData.pincode then
            BANK.LogTransaction(source,string.upper(key), string.upper(key), amount, bankMoney)
        end

        TriggerClientEvent("esx_banking:updateMoneyInUI", source, key, bankMoney, money, invested)
    end
end)

-- register callbacks
ESX.RegisterServerCallback("esx_banking:getPlayerData", function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.getIdentifier()
    local weekAgo = (os.time() - 604800) * 1000
    local transactionHistory = MySQL.Sync.fetchAll(
        'SELECT * FROM banking WHERE identifier = ? AND time > ? ORDER BY time DESC LIMIT 10', {identifier, weekAgo})
    local playerData = {
        playerName = xPlayer.getName(),
        money = xPlayer.getAccount('money').money,
        bankMoney = xPlayer.getAccount('bank').money,
        transactionHistory = transactionHistory,
        invested = 0
    }

    if xPlayer.getAccount('invested') then
        playerData['invested'] = xPlayer.getAccount('invested').money
    else
        playerData['invested'] = 0
    end

    cb(playerData)
end)

ESX.RegisterServerCallback("esx_banking:checkPincode", function(source, cb, inputPincode)
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.getIdentifier()
    local pincode = MySQL.Sync.fetchScalar('SELECT COUNT(1) AS pincode FROM users WHERE identifier = ? AND pincode = ?',
        {identifier, inputPincode})
    cb(pincode > 0)
end)

function logTransaction(targetSource,label, key,amount)
    if targetSource == nil then
        print("ERROR: TargetSource nil!")
        return
    end

    if key == nil then
        print("ERROR: Do you need use these: WITHDRAW,DEPOSIT,INVEST,RETRIEVE,TRANSFER_RECEIVE")
        return
    end
    
    if type(key) ~= "string" or key == '' then
        print("ERROR: Do you need use these: WITHDRAW,DEPOSIT,INVEST,RETRIEVE,TRANSFER_RECEIVE and can only be string type!")
        return
    end

    if amount == nil then
        print("ERROR: Amount value is nil! Add some numeric value to the amount!")
        return
    end

    if label == nil then
        label = "UNKNOW LABEL"
    end

    local xPlayer = ESX.GetPlayerFromId(tonumber(targetSource))

    if xPlayer ~= nil then
        local bankCurrentMoney = xPlayer.getAccount('bank').money
        BANK.LogTransaction(targetSource, label, string.upper(key), amount, bankCurrentMoney)  
    else
        print("ERROR: xPlayer is nil!") 
    end
end
exports("logTransaction", logTransaction)

RegisterServerEvent('esx_banking:logTransaction')
AddEventHandler('esx_banking:logTransaction', function(label,key,amount)
    logTransaction(source,label,key,amount)
end)

-- bank functions
BANK = {
    CreatePeds = function()
        for i = 1, #Config.Peds do
            local model = Config.Peds[i].Model
            local coords = Config.Peds[i].Position
            spawnedPeds[i] = CreatePed(0, model, coords.x, coords.y, coords.z, coords.w, true, true)
            netIdTable[i] = NetworkGetNetworkIdFromEntity(spawnedPeds[i])
            while not DoesEntityExist(spawnedPeds[i]) do Wait(50) end
        end

        Wait(100)
        TriggerClientEvent('esx_banking:PedHandler', -1, netIdTable)
    end,
    DeletePeds = function()
        for i = 1, #spawnedPeds do
            DeleteEntity(spawnedPeds[i])
            spawnedPeds[i] = nil
        end
    end,
    Withdraw = function(amount, xPlayer)
        xPlayer.addAccountMoney('money', amount)
        xPlayer.removeAccountMoney('bank', amount)
    end,
    Deposit = function(amount, xPlayer)
        xPlayer.removeAccountMoney('money', amount)
        xPlayer.addAccountMoney('bank', amount)
    end,
    Invest = function(amount, xPlayer)
        if amount < 1000 then
            TriggerClientEvent("esx:showNotification", source, TranslateCap("cant_do_it"), "error")
            return false
        end
        xPlayer.removeAccountMoney('bank', amount)
        xPlayer.addAccountMoney('invested', amount)
    end,
    Retrieve = function(amount, xPlayer)
        xPlayer.removeAccountMoney('invested', amount)
        xPlayer.addAccountMoney('bank', amount)
    end,
    Transfer = function(xTarget, xPlayer, amount, key)
        if xTarget == nil or xPlayer.source == xTarget.source then
            TriggerClientEvent("esx:showNotification", source, TranslateCap("cant_do_it"), "error")
            return false
        end

        xPlayer.removeAccountMoney('bank', amount)
        xTarget.addAccountMoney('bank', amount)
        local bankMoney = xTarget.getAccount('bank').money
        BANK.LogTransaction(xTarget.source, "TRANSFER_RECEIVE", amount, bankMoney)
        TriggerClientEvent("esx:showNotification", xTarget.source, TranslateCap('receive_transfer', amount, xPlayer.source),
            "success")

        return true
    end,
    Pincode = function(amount, identifier)
        MySQL.update('UPDATE users SET pincode = ? WHERE identifier = ? ', {amount, identifier})
    end,
    LogTransaction = function(playerId, label, logType, amount, bankMoney)
        if playerId == nil then
            return
        end

        if label == nil then
            label = logType
        end

        local xPlayer = ESX.GetPlayerFromId(playerId)
        local identifier = xPlayer.getIdentifier()
    
        MySQL.insert('INSERT INTO banking (identifier, label, type, amount, time, balance) VALUES (?, ?, ?, ?, ?, ?)',
            {identifier,label,logType,amount, os.time() * 1000, bankMoney})
    end   
}
