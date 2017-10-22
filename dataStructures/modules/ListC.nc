/**
 * ANDES Lab - University of California, Merced
 * This class provides a simple list.
 *
 * @author UCM ANDES Lab
 * @author Alex Beltran
 * @date   2013/09/03
 *
 */

generic module ListC(typedef t, int n){
	provides interface List<t>;
}

implementation{
	uint16_t MAX_SIZE = n;

	t container[n];
	uint16_t size = 0;

	command void List.pushback(t input){
		// Check to see if we have room for the input.
		if(size < MAX_SIZE){
			// Put it in.
			container[size] = input;
			size++;
		}
	}

	command void List.pushfront(t input){
		// Check to see if we have room for the input.
		if(size < MAX_SIZE){
			int32_t i;
			// Shift everything to the right.
			for(i = size-1; i>=0; i--){
				container[i+1] = container[i];
			}

			container[0] = input;
			size++;
		}
	}

	command t List.popback(){
		t returnVal;

		returnVal = container[size];
		// We don't need to actually remove the value, we just need to decrement
		// the size.
		if(size > 0)size--;
		return returnVal;
	}

	command t List.popfront(){
		t returnVal;
		uint16_t i;

		returnVal = container[0];
		if(size>0){
			// Move everything to the left.
			for(i = 0; i<size-1; i++){
				container[i] = container[i+1];
			}
			size--;
		}

		return returnVal;
	}

	// This is similar to peek head.
	command t List.front(){
		return container[0];
	}

	// Peek tail
	command t List.back(){
		return container[size];
	}

	command bool List.isEmpty(){
		if(size == 0)
			return TRUE;
		else
			return FALSE;
	}

	command bool List.isFull()
	{
		if (size == MAX_SIZE)
			return TRUE;
		else return FALSE;
	}

	command uint16_t List.size(){
		return size;
	}

	command t* List.get(uint16_t position){
		return &container[position];
	}

	command t List.remove(uint8_t position)
	{
			t item_to_remove;
			uint8_t i = 0;
			item_to_remove = container[position];		//get item position in container
			for(i = position; i > 0; i--)
			{
				container[i] = container[i-1];			//move all the elements above the item position one index down. 
			}
			container[0] = item_to_remove;				//move item we dont want to front
			item_to_remove = call List.popfront();		//pop the front
			return item_to_remove;
	}
}
