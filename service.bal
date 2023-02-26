import ballerina/http;
import ballerina/jwt;
// import wso2/choreo.sendemail as sendemail;
import ballerina/email;

import ballerina/log;
import ballerina/io;
import ballerina/regex;

const string CONST_X_JWT_ASSERTION = "x-jwt-assertion";
const string CONST_SUB_CLAIM = "sub";
const string CONST_USERNAME_CLAIM = "username";
const string CONST_PRICE = "PRICE";
const string CONST_TITLE = "TITLE";

configurable EmailServerConfig emailServerConfig = ?;

# A service representing a network-accessible API
# bound to port `9090`.
service /ecomm on new http:Listener(9090) {

    resource function get itemsforuser(@http:Header {name: CONST_X_JWT_ASSERTION} string? authHeader) returns Item[]|ItemWithSubscription[]|error {
        if authHeader != () {
            var jwtTokenPayLoad = check jwt:decode(authHeader);
            var userId = jwtTokenPayLoad[1][CONST_SUB_CLAIM];
            // log:printInfo(CONST_SUB_CLAIM, userId = userId);
            // string userId = "d772c9f6-2807-4556-ba59-7ca9743428a2"; //for debugging
            if userId != () {
                var userSubscriptions = userSubscriptions.filter(subscription => subscription.userId == userId);
                ItemWithSubscription[] items = from var item in itemTable
                    select {...item, isSubscribed: userSubscriptions.hasKey([userId, item.id])};
                return items;
            }
        }
        return itemTable.toArray();
    }

    //A resource function that returns all the items in the itemsTable
    resource function get items() returns Item[] {
        return itemTable.toArray();
    }

    resource function post items(@http:Payload Item[] itemEntries)
                                    returns Item[]|ConflictingItemCodesError {

        string[] conflictingIDs = from Item itemEntry in itemEntries
            where itemTable.hasKey(itemEntry.id)
            select itemEntry.id;

        if conflictingIDs.length() > 0 {
            return {
                body: {
                    errmsg: string:'join(" ", "Conflicting Item Codes:", ...conflictingIDs)
                }
            };
        } else {
            foreach var itemEntry in itemEntries {
                itemEntry.isAvailable = true;
                itemTable.add(itemEntry);
            }
            return itemEntries;
        }
    }

    //* A resource function to get an item by id from the itemsTable
    resource function get items/[string id]() returns Item|InvalidItemCodeError {
        Item? itemEntry = itemTable[id];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${id}`
                }
            };
        }
        return itemEntry;
    }

    // A resource function to get a subscription and add it to the subscription table
    resource function post subscriptions(@http:Payload Subscription subscription, @http:Header {name: CONST_X_JWT_ASSERTION} string? authHeader) returns InvalidItemCodeError?|error {

        Item? itemEntry = itemTable[subscription.itemId];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${subscription.itemId}`
                }
            };
        }

        string? userId = "";

        // Get the userId from the authHeader
        if authHeader != () {
            var jwtTokenPayLoad = check jwt:decode(authHeader);
            userId = jwtTokenPayLoad[1][CONST_SUB_CLAIM];
            log:printInfo("[x-jwt-assertion]", jwtTokenPayLoad = jwtTokenPayLoad);
            log:printInfo("[userid]", userId = userId);
            // string userId = "d772c9f6-2807-4556-ba59-7ca9743428a2";
            if userId != () {
                Subscription newSubscription = {
                    userId: userId,
                    itemId: subscription.itemId
                };

                //check whether the subscription is already available
                if userSubscriptions.hasKey([newSubscription.userId, newSubscription.itemId]) {
                    return {
                        body: {
                            errmsg: string `Subscription already exists for Item Code: ${newSubscription.itemId}`
                        }
                    };
                }
                userSubscriptions.add(newSubscription); // add subscription to the subscription table

                // add an item to the customers table with userid and email if it does not exist
                if !customers.hasKey(newSubscription.userId) {
                    var email = jwtTokenPayLoad[1][CONST_USERNAME_CLAIM].toString();
                    log:printInfo(CONST_USERNAME_CLAIM, email = email);
                    customers.add({id: newSubscription.userId, email: email});
                }

            }
        }

        return;
    }

    //A resource function to delete a subscription for a given itemId in the request, by reading the userId from the JWT token
    resource function delete subscriptions/[string itemId](@http:Header {name: CONST_X_JWT_ASSERTION} string? authHeader)
                                                            returns InvalidItemCodeError?|error {

        if authHeader != () {
            var jwtTokenPayLoad = check jwt:decode(authHeader);
            var userId = jwtTokenPayLoad[1][CONST_SUB_CLAIM];
            // log:printInfo("[x-jwt-assertion]", userId = userId);
            // string userId = "d772c9f6-2807-4556-ba59-7ca9743428a2";
            if userId != () {
                Item? itemEntry = itemTable[itemId];
                if itemEntry is () {
                    return {
                        body: {
                            errmsg: string `Invalid Item Code: ${itemId}`
                        }
                    };
                }
                //check whether the subscription is already available
                if !userSubscriptions.hasKey([userId, itemId]) {
                    return {
                        body: {
                            errmsg: string `Subscription does not exist for Item Code: ${itemId}`
                        }
                    };
                }
                _ = userSubscriptions.remove([userId, itemId]);
                return;
            }
        }
        return {
            body: {
                errmsg: string `Invalid JWT token`
            }
        };
    }

    // A resource function to update fields of an item in the ItemTable for a item.id specified in the path
    resource function put items/[string id]/update(@http:Payload Item item) returns Item|InvalidItemCodeError {
        Item? itemEntry = itemTable[id];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${id}`
                }
            };
        }
        decimal? oldPrice = itemEntry.price;
        itemEntry.imageUrl = item.imageUrl;
        itemEntry.title = item.title;
        itemEntry.description = item.description;
        itemEntry.price = item.price;
        itemEntry.isAvailable = item.isAvailable;
        itemEntry.includes = item.includes;
        itemEntry.intendedFor = item.intendedFor;
        itemEntry.color = item.color;
        itemEntry.material = item.material;
        
        // Send an email to the subscribers if the price of the item is reduced
        _ = start sendEmail(itemEntry, oldPrice, item.price);

        return itemEntry;
    }

    // A resource function to patch a field of an item in the ItemTable for a item.id specified in the path
    resource function patch items/[string id]/update(@http:Payload Item updatedItem) returns Item|InvalidItemCodeError|error {
        Item? itemEntry = itemTable[id];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${id}`
                }
            };
        }
        if updatedItem.imageUrl != () {
            itemEntry.imageUrl = updatedItem.imageUrl;
        }
        if updatedItem.title != () {
            itemEntry.title = updatedItem.title;
        }
        if updatedItem.description != () {
            itemEntry.description = updatedItem.description;
        }
        if updatedItem.price != () {
            decimal? oldPrice = itemEntry.price;
            itemEntry.price = updatedItem.price;
            _ = start sendEmail(itemEntry, oldPrice, updatedItem.price);
        }
        if updatedItem.isAvailable != () {
            itemEntry.isAvailable = updatedItem.isAvailable;
        }
        if updatedItem.includes != () {
            itemEntry.includes = updatedItem.includes;
        }
        if updatedItem.intendedFor != () {
            itemEntry.intendedFor = updatedItem.intendedFor;
        }
        if updatedItem.color != () {
            itemEntry.color = updatedItem.color;
        }
        if updatedItem.material != () {
            itemEntry.material = updatedItem.material;
        }
        return itemEntry;
    }

}

public type Item record {|
    readonly string id;
    string? imageUrl;
    string? title;
    string? description;
    decimal? price;
    boolean? 'isAvailable;
    string? includes;
    string? intendedFor;
    string? color;
    string? material;
|};

public type ItemWithSubscription record {|
    *Item;
    boolean isSubscribed;
|};

public type Address record {|
    string city;
    string street;
    string postalcode;
    string locationLink;
|};

public type Customer record {|
    readonly string id;
    string email;
|};

// A type representing user subscription to an item
public type Subscription record {|
    readonly string userId;
    readonly string itemId;
|};

// A type representing the emailServer configuration
public type EmailServerConfig record {|
    string host;
    string username;
    string password;
    int port;
|};

//* a table with sample subscription data as a Subscription record array
public final table<Subscription> key(userId, itemId) userSubscriptions = table [
        {
            userId: "d772c9f6-2807-4556-ba59-7ca9743428a2",
            itemId: "9781623363586"
        }
    ];

//* a table with userid and email data as a « record array
public final table<Customer> key(id) customers = table [
        {
            id: "d772c9f6-2807-4556-ba59-7ca9743428a2",
            email: "ayshsandu@gmail.com"
        }
    ];

//* a table with sample item data as a Item record array
public final table<Item> key(id) itemTable = table [
        {
            id: "9780743273565",
            imageUrl: "https://s.yimg.com/lo/api/res/1.2/V04hK2wI1fFem4IFxZXXIQ--/YXBwaWQ9ZWNfaG9yaXpvbnRhbDtoPTQwMDtzcz0xO3c9NDAw/http://s7d6.scene7.com/is/image/PetSmart/5334729.cf.jpg",
            title: "Top Paw® Valentine's Day Single Dog Sweater",
            description: "Dress your pup up appropriately for Valentine's Day with this Top Paw Valentine's Day Kisses Dog Sweater. This sweet sweater slips on and off easily while offering a comfortable fit, and lets it be known that your pup is single and ready to mingle",
            isAvailable: true,
            price: 5.0,
            includes: "1 Sweater",
            intendedFor: "Small Dogs",
            color: "Red",
            material: "Cotton"
        },
        {
            id: "9781623363586",
            imageUrl: "https://m.media-amazon.com/images/I/51zTNwiClXL.jpg",
            title: "PetSafe® Automatic Ball Launcher",
            description: "Keep your furry friend entertained for hours with the PetSafe Automatic Ball Launcher. This interactive toy launches standard-sized tennis balls up to 30 feet away, allowing your dog to chase and retrieve them without any effort from you. With multiple safety sensors and automatic rest periods, it's the perfect toy for energetic dogs who need a little extra exercise.",
            isAvailable: true,
            price: 150.0,
            includes: "1 Automatic Ball Launcher, 3 Tennis Balls",
            intendedFor: "Medium to Large Dogs",
            color: "Purple,Grey",
            material: "Plastic"
        },
        {
            id: "9781510724542",
            imageUrl: "https://m.media-amazon.com/images/I/71aVxw+AKIL._AC_UF894,1000_QL80_.jpg",
            title: "Pogi's Poop Bags",
            description: "Make cleaning up after your dog a little less unpleasant with Pogi's Poop Bags. Made from high-quality, eco-friendly materials, these bags are strong, leak-proof, and deodorized, ensuring a clean and hygienic pick-up every time. Plus, the bright and colorful design makes them easy to spot in any setting.",
            isAvailable: true,
            price: 12.99,
            includes: "300 Poop Bags",
            intendedFor: "Dog Owners",
            color: "Green, Blue, Purple",
            material: "Biodegradable Plastic"
        }
        // {
        //     id: "9781452151342",
        //     imageUrl: "https://images.squarespace-cdn.com/content/v1/56b27cd486db4396b83ed266/1585343422671-I92GY8S1288YJAGBT7OY/Willow%2Bthe%2BCorgi%2BDog%2BHouse.jpg",
        //     title: "Barkitecture: Designer Dog Houses",
        //     description: "Upgrade your dog's living space with Barkitecture, a stunning collection of designer dog houses. Featuring 20 unique designs from leading architects and designers, this book showcases the latest trends in dog house design, from minimalist modernism to cozy cottage style. It's the perfect inspiration for anyone looking to build or renovate their pup's home.",
        //     isAvailable: true,
        //     price: 29.99,
        //     includes: "1 Hardcover Book",
        //     intendedFor: "Dog Owners",
        //     color: "Multicolor",
        //     material: "Paper"
        // }

    ];

public type ConflictingItemCodesError record {|
    *http:Conflict;
    ErrorMsg body;
|};

public type InvalidItemCodeError record {|
    *http:NotFound;
    ErrorMsg body;
|};

public type ErrorMsg record {|
    string errmsg;
|};

//* A function to get the emails of the users who subscribed to a particular item
# Description
# + itemId - Item Id to get subscriptions 
# + return - Emails of users subscribed to the item
public function getEmails(string itemId) returns string[] {
    var subscriptions = userSubscriptions.filter(s => s.itemId == itemId);
    return from var subscription in subscriptions
        select customers.get(subscription.userId).email;
}

//* function to send an email to the user when a new item is added using ballerina email connector
# Using https://mailtrap.io/ as SMPT server
# + item - Parameter Description  
# + oldPrice - OldPrice of the item  
# + newPrice - NewPrice of the item
# + return - Error if the email sending fails
function sendEmail(Item item, decimal? oldPrice, decimal? newPrice) returns error? {

    if (newPrice < oldPrice) {
        string[] emails = getEmails(item.id);
        // log:printInfo("BCC Address", emails = emailsString);

        // Define a html body for the email with item update details
        string readContent = check io:fileReadString("./tmp/Email.html");
        var title = item.title ?: "No Title";
        var price = newPrice.toString();

        readContent = regex:replaceAll(readContent, CONST_TITLE, title);
        readContent = regex:replaceAll(readContent, CONST_PRICE, price);
        log:printInfo("Emails: ", emails = emails);

        //Send email with choreo email connector
        // _ = check emailClient->sendEmail("*****@wso2.com", readContent, "", emailsString);

        //Send email with SmtpClient
        email:SmtpConfiguration smtpConfig = {
            port: emailServerConfig.port,
            security: email:START_TLS_AUTO
        };

        // create smtp client with connection parameters (https://mailtrap.io/)
        email:SmtpClient smtpClient = check new (emailServerConfig.host, emailServerConfig.username, emailServerConfig.password, smtpConfig);
        email:Message email = {
            to: emails,
            cc: [],
            bcc: emails,
            subject: "[PetStore] Price Drop for " + title,
            body: readContent,
            'from: "smtp.mailtrap.io",
            sender: "smtp.mailtrap.io",
            replyTo: ["replyTo1@ecomm.com", "replyTo2@ecomm.com"],
            headers: {
                "Content-Type": "text/html"
            }
        };

        log:printInfo("Email emailServerUsername ", emailConfig = emailServerConfig.toString());
        // call smtp client asynchronous send
        _ = start smtpClient->sendMessage(email);
    }

}
