package main

import (
	"fmt"
	"github.com/golang/protobuf/proto"
	"github.com/golang/protobuf/ptypes/empty"
	"github.com/jhump/protoreflect/desc/builder"
	"github.com/jhump/protoreflect/dynamic"
	"regexp"
	"sync"
)

// When we don't have an actual proto message descriptor, this takes a best effort
// approach to generating one. It's definitely not perfect but is more useful than nothing.

var (
	asciiPattern        = regexp.MustCompile(`^[ -~]*$`)
	messageCounter      = 0
	messageCounterMutex = sync.Mutex{}
)

// All messages must have unique names, this function generates them
func getNewMessageName() string {
	messageCounterMutex.Lock()
	defer messageCounterMutex.Unlock()
	messageCounter++
	return fmt.Sprintf("unknown_message_%d", messageCounter)
}

// This takes a dynamic.Message of unknown type and returns
// a message descriptor which will mean all fields are included
// in the JSON output.
// TODO: this would probably be better implemented within github.com/jhump/protoreflect
func generateDescriptorForUnknownMessage(message *dynamic.Message) *builder.MessageBuilder {
	fields := map[int32][]dynamic.UnknownField{}
	for _, unknownFieldNum := range message.GetUnknownFields() {
		fields[unknownFieldNum] = message.GetUnknownField(unknownFieldNum)
	}
	return makeDescriptorForFields(fields)
}

func makeDescriptorForFields(fields map[int32][]dynamic.UnknownField) *builder.MessageBuilder {
	msg := builder.NewMessage(getNewMessageName())
	for fieldNum, instances := range fields {
		var fieldType *builder.FieldType
		// TODO: look at all instances and merge the discovered fields together
		// This way repeated sub messages are handled properly (i.e. where the full type information
		// might not be inferable from just the first message)
		switch instances[0].Encoding {
		// TODO: handle all wire types
		case proto.WireBytes:
			fieldType = handleWireBytes(instances[0])
		default:
			// Fixed precision number
			fieldType = builder.FieldTypeFixed64()
		}
		field := builder.NewField(fmt.Sprintf("_%d", fieldNum), fieldType)
		field.SetNumber(fieldNum)
		if len(instances) > 1 {
			field.SetRepeated()
		}
		msg.AddField(field)
	}

	return msg
}

func handleWireBytes(instance dynamic.UnknownField) *builder.FieldType {
	if asciiPattern.Match(instance.Contents) {
		// highly unlikely that an entirely ASCII string is actually an embedded proto message
		// TODO: make this heuristic cleverer
		return builder.FieldTypeString()
	}
	// embedded messages are encoded on the wire as strings
	// so try to decode this string as a message
	dyn, err := dynamic.AsDynamicMessage(&empty.Empty{})
	if err != nil {
		panic(err)
	}
	err = proto.Unmarshal(instance.Contents, dyn)
	if err != nil {
		// looks like it wasn't a valid proto message
		return builder.FieldTypeString()
	}
	return builder.FieldTypeMessage(generateDescriptorForUnknownMessage(dyn))
}